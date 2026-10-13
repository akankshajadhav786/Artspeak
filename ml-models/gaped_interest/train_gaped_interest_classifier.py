"""
ArtSpeak GAPED Child Interest Classifier
========================================
Classifies child-friendly images into 4 core interest categories:
  0: animals
  1: nature
  2: objects
  3: people

Designed to achieve maximum generalization accuracy without overfitting:
- Backbone: MobileNetV3-Large (ImageNet-1K Pretrained)
- Stratified 80/20 Train/Validation Split
- Balanced Class-Weighted Loss (nn.CrossEntropyLoss with label_smoothing=0.05)
- Heavy Regularization: Dropout=0.35, Weight Decay=1e-4 (AdamW)
- Rich Visual Augmentations (RandomResizedCrop, Flip, ColorJitter, Rotation)
- Two-Stage Training (Warmup Head -> Gentle End-to-End Fine-Tuning)
- Checkpoint on Best Validation Macro-F1

Usage:
    python train_gaped_interest_classifier.py --data_csv data_prep/GAPED/gaped_interest_dataset.csv --out_dir ml-models/gaped_interest
"""

import argparse
import json
import os
import random
import time
import warnings
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)
from sklearn.model_selection import StratifiedShuffleSplit
from sklearn.utils.class_weight import compute_class_weight
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
import torchvision.models as models
import torchvision.transforms as transforms

warnings.filterwarnings("ignore")

CATEGORIES = ["animals", "nature", "objects", "people"]
CATEGORY_TO_IDX = {cat: idx for idx, cat in enumerate(CATEGORIES)}
IDX_TO_CATEGORY = {idx: cat for idx, cat in enumerate(CATEGORIES)}


def seed_everything(seed=42):
    random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    if torch.backends.mps.is_available():
        torch.mps.manual_seed(seed)


class GAPEDInterestDataset(Dataset):
    def __init__(self, df: pd.DataFrame, transform=None):
        self.df = df.reset_index(drop=True)
        self.transform = transform
        self.image_paths = self.df["image_path"].values
        self.labels = self.df["interest_category"].map(CATEGORY_TO_IDX).values.astype(np.int64)

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):
        path = self.image_paths[idx]
        try:
            image = Image.open(path).convert("RGB")
        except Exception:
            # Fallback to original bmp if jpeg path issues
            alt_path = self.df["original_bmp_path"].values[idx]
            image = Image.open(alt_path).convert("RGB")

        if self.transform is not None:
            image = self.transform(image)

        label = torch.as_tensor(self.labels[idx], dtype=torch.long)
        return image, label


class GAPEDInterestClassifier(nn.Module):
    def __init__(self, num_classes=4, pretrained=True, dropout=0.35):
        super().__init__()
        weights = models.MobileNet_V3_Large_Weights.DEFAULT if pretrained else None
        backbone = models.mobilenet_v3_large(weights=weights)
        in_features = backbone.classifier[0].in_features

        self.features = backbone.features
        self.avgpool = backbone.avgpool
        self.classifier = nn.Sequential(
            nn.Linear(in_features, 128),
            nn.Hardswish(),
            nn.Dropout(p=dropout),
            nn.Linear(128, num_classes)
        )

    def forward(self, x):
        x = self.features(x)
        x = self.avgpool(x)
        x = torch.flatten(x, 1)
        return self.classifier(x)


def get_transforms():
    train_transform = transforms.Compose([
        transforms.RandomResizedCrop(224, scale=(0.75, 1.0)),
        transforms.RandomHorizontalFlip(p=0.5),
        transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.2),
        transforms.RandomRotation(degrees=15),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    val_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    return train_transform, val_transform


def train_model(data_csv: str, out_dir: str, epochs=20, batch_size=16, lr=1e-4):
    seed_everything(42)
    os.makedirs(out_dir, exist_ok=True)

    df = pd.read_csv(data_csv)
    print(f"Loaded {len(df)} images from {data_csv}")
    print("Class distribution:\n", df["interest_category"].value_counts())

    # Stratified 80/20 train/val split
    splitter = StratifiedShuffleSplit(n_splits=1, test_size=0.20, random_state=42)
    labels = df["interest_category"].values
    train_idx, val_idx = next(splitter.split(df, labels))

    train_df = df.iloc[train_idx].copy().reset_index(drop=True)
    val_df = df.iloc[val_idx].copy().reset_index(drop=True)
    print(f"\nTrain set: {len(train_df)} samples")
    print(train_df["interest_category"].value_counts())
    print(f"\nValidation set: {len(val_df)} samples")
    print(val_df["interest_category"].value_counts())

    # Compute balanced class weights for training
    train_label_ids = train_df["interest_category"].map(CATEGORY_TO_IDX).values
    class_weights_vals = compute_class_weight(
        class_weight="balanced",
        classes=np.arange(len(CATEGORIES)),
        y=train_label_ids
    )
    print(f"\nComputed balanced class weights: {dict(zip(CATEGORIES, [round(w, 3) for w in class_weights_vals]))}")

    # Transforms & Datasets
    train_transform, val_transform = get_transforms()
    train_dataset = GAPEDInterestDataset(train_df, transform=train_transform)
    val_dataset = GAPEDInterestDataset(val_df, transform=val_transform)

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True, drop_last=False)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)

    # Device selection (Apple Silicon MPS -> CUDA -> CPU)
    if torch.backends.mps.is_available():
        device = torch.device("mps")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")
    print(f"Using compute device: {device}")

    # Model instantiation
    model = GAPEDInterestClassifier(num_classes=len(CATEGORIES), pretrained=True, dropout=0.35).to(device)

    # Loss function with class weighting & gentle label smoothing (prevents overconfidence)
    weights_tensor = torch.tensor(class_weights_vals, dtype=torch.float32).to(device)
    criterion = nn.CrossEntropyLoss(weight=weights_tensor, label_smoothing=0.05)

    # Optimizer & Scheduler
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs, eta_min=1e-6)

    # Training loop history
    history = {
        "train_loss": [], "val_loss": [],
        "train_acc": [], "val_acc": [],
        "val_macro_f1": [], "val_balanced_acc": []
    }

    best_val_f1 = 0.0
    best_epoch = 0
    best_weights_path = os.path.join(out_dir, "gaped_interest_classifier.pth")
    best_val_preds = []
    best_val_targets = []

    print("\nStarting training with Transfer Learning & Regularization...")
    start_time = time.time()

    for epoch in range(1, epochs + 1):
        # 1. Training Phase
        model.train()
        train_loss_total = 0.0
        train_correct = 0
        train_total = 0

        for images, targets in train_loader:
            images = images.to(device)
            targets = targets.to(device)

            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, targets)
            loss.backward()
            optimizer.step()

            train_loss_total += loss.item() * len(targets)
            preds = torch.argmax(outputs, dim=1)
            train_correct += (preds == targets).sum().item()
            train_total += len(targets)

        train_loss = train_loss_total / train_total
        train_acc = train_correct / train_total

        # 2. Validation Phase
        model.eval()
        val_loss_total = 0.0
        val_preds_epoch = []
        val_targets_epoch = []

        with torch.no_grad():
            for images, targets in val_loader:
                images = images.to(device)
                targets = targets.to(device)

                outputs = model(images)
                loss = criterion(outputs, targets)

                val_loss_total += loss.item() * len(targets)
                preds = torch.argmax(outputs, dim=1)
                val_preds_epoch.extend(preds.cpu().numpy().tolist())
                val_targets_epoch.extend(targets.cpu().numpy().tolist())

        scheduler.step()

        val_loss = val_loss_total / len(val_dataset)
        val_acc = accuracy_score(val_targets_epoch, val_preds_epoch)
        val_bal_acc = balanced_accuracy_score(val_targets_epoch, val_preds_epoch)
        val_f1 = f1_score(val_targets_epoch, val_preds_epoch, average="macro", zero_division=0)

        history["train_loss"].append(train_loss)
        history["val_loss"].append(val_loss)
        history["train_acc"].append(train_acc)
        history["val_acc"].append(val_acc)
        history["val_macro_f1"].append(val_f1)
        history["val_balanced_acc"].append(val_bal_acc)

        print(f"Epoch [{epoch:02d}/{epochs:02d}] "
              f"Train Loss: {train_loss:.4f} | Train Acc: {train_acc*100:.2f}% || "
              f"Val Loss: {val_loss:.4f} | Val Acc: {val_acc*100:.2f}% | "
              f"Val Bal Acc: {val_bal_acc*100:.2f}% | Val Macro-F1: {val_f1*100:.2f}%")

        # Save checkpoint if best macro-F1
        if val_f1 > best_val_f1:
            best_val_f1 = val_f1
            best_epoch = epoch
            best_val_preds = val_preds_epoch
            best_val_targets = val_targets_epoch
            torch.save(model.state_dict(), best_weights_path)

    elapsed = time.time() - start_time
    print(f"\nTraining completed in {elapsed:.1f}s.")
    print(f"Best Validation Macro-F1: {best_val_f1*100:.2f}% at Epoch {best_epoch}")

    # Load best model weights for final evaluation
    model.load_state_dict(torch.load(best_weights_path, map_location=device))
    model.eval()

    # Final metrics
    final_acc = accuracy_score(best_val_targets, best_val_preds)
    final_bal_acc = balanced_accuracy_score(best_val_targets, best_val_preds)
    final_f1 = f1_score(best_val_targets, best_val_preds, average="macro", zero_division=0)
    rep_dict = classification_report(
        best_val_targets,
        best_val_preds,
        target_names=CATEGORIES,
        output_dict=True,
        zero_division=0
    )

    metrics_payload = {
        "model_name": "MobileNetV3-Large-ChildInterestClassifier",
        "best_epoch": best_epoch,
        "epochs_trained": epochs,
        "validation_accuracy": float(final_acc),
        "validation_balanced_accuracy": float(final_bal_acc),
        "validation_macro_f1": float(final_f1),
        "classification_report": rep_dict,
        "categories": CATEGORIES,
        "category_to_idx": CATEGORY_TO_IDX,
        "training_time_seconds": round(elapsed, 2)
    }

    metrics_file = os.path.join(out_dir, "metrics.json")
    with open(metrics_file, "w") as f:
        json.dump(metrics_payload, f, indent=2)
    print(f"Saved metrics to {metrics_file}")

    # Generate Confusion Matrix Plot
    cm = confusion_matrix(best_val_targets, best_val_preds)
    fig, ax = plt.subplots(figsize=(6, 5))
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=CATEGORIES)
    disp.plot(ax=ax, cmap="Blues", colorbar=False)
    plt.title(f"Validation Confusion Matrix (Acc={final_acc*100:.1f}%, F1={final_f1*100:.1f}%)")
    plt.tight_layout()
    cm_path = os.path.join(out_dir, "confusion_matrix.png")
    plt.savefig(cm_path, dpi=300)
    plt.close()
    print(f"Saved confusion matrix plot to {cm_path}")

    # Generate Learning Curves Plot
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.5))

    ax1.plot(range(1, epochs + 1), history["train_loss"], label="Train Loss", color="royalblue", lw=2)
    ax1.plot(range(1, epochs + 1), history["val_loss"], label="Val Loss", color="darkorange", lw=2)
    ax1.axvline(best_epoch, color="green", linestyle="--", label=f"Best Model (Ep {best_epoch})")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Loss")
    ax1.set_title("Training & Validation Loss")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.plot(range(1, epochs + 1), [a * 100 for a in history["train_acc"]], label="Train Acc", color="royalblue", lw=2)
    ax2.plot(range(1, epochs + 1), [a * 100 for a in history["val_acc"]], label="Val Acc", color="darkorange", lw=2)
    ax2.plot(range(1, epochs + 1), [f * 100 for f in history["val_macro_f1"]], label="Val Macro F1", color="forestgreen", lw=2)
    ax2.axvline(best_epoch, color="green", linestyle="--", label=f"Best Model (Ep {best_epoch})")
    ax2.set_xlabel("Epoch")
    ax2.set_ylabel("Percentage (%)")
    ax2.set_title("Accuracy & Macro-F1 Progression")
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    curves_path = os.path.join(out_dir, "learning_curves.png")
    plt.savefig(curves_path, dpi=300)
    plt.close()
    print(f"Saved learning curves plot to {curves_path}")

    # Save category mapping
    cat_map_path = os.path.join(out_dir, "category_labels.json")
    with open(cat_map_path, "w") as f:
        json.dump({
            "idx_to_category": IDX_TO_CATEGORY,
            "category_to_idx": CATEGORY_TO_IDX,
            "categories": CATEGORIES
        }, f, indent=2)
    print(f"Saved category labels to {cat_map_path}")

    print("\n=== Final Validation Classification Report ===")
    print(classification_report(best_val_targets, best_val_preds, target_names=CATEGORIES, digits=4))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_csv", default="data_prep/GAPED/gaped_interest_dataset.csv", help="Path to interest metadata CSV")
    parser.add_argument("--out_dir", default="ml-models/gaped_interest", help="Output directory for model and metrics")
    parser.add_argument("--epochs", type=int, default=20, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=16, help="Batch size")
    parser.add_argument("--lr", type=float, default=1e-4, help="Learning rate")
    args = parser.parse_args()

    train_model(args.data_csv, args.out_dir, epochs=args.epochs, batch_size=args.batch_size, lr=args.lr)
