"""
Inference Module for Child Interest Classification
---------------------------------------------------
Loads the trained MobileNetV3-Large interest classifier and predicts
the child interest category ('animals', 'nature', 'objects', 'people')
for any input image.
"""

import json
import os
from typing import Dict, Union
from PIL import Image
import torch
import torch.nn as nn
import torchvision.models as models
import torchvision.transforms as transforms

MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
WEIGHTS_PATH = os.path.join(MODEL_DIR, "gaped_interest_classifier.pth")
LABELS_PATH = os.path.join(MODEL_DIR, "category_labels.json")

class GAPEDInterestPredictor:
    def __init__(self, weights_path: str = WEIGHTS_PATH, labels_path: str = LABELS_PATH):
        with open(labels_path, "r") as f:
            metadata = json.load(f)
            self.categories = metadata["categories"]
            self.idx_to_cat = {int(k): v for k, v in metadata["idx_to_category"].items()}
            
        if torch.backends.mps.is_available():
            self.device = torch.device("mps")
        elif torch.cuda.is_available():
            self.device = torch.device("cuda")
        else:
            self.device = torch.device("cpu")
            
        # Instantiate backbone & head
        backbone = models.mobilenet_v3_large(weights=None)
        in_features = backbone.classifier[0].in_features
        backbone.classifier = nn.Sequential(
            nn.Linear(in_features, 128),
            nn.Hardswish(),
            nn.Dropout(p=0.35),
            nn.Linear(128, len(self.categories))
        )
        
        state_dict = torch.load(weights_path, map_location=self.device)
        backbone.load_state_dict(state_dict)
        backbone.to(self.device)
        backbone.eval()
        self.model = backbone
        
        self.transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])

    def predict(self, image_input: Union[str, Image.Image]) -> Dict:
        if isinstance(image_input, str):
            image = Image.open(image_input).convert("RGB")
        else:
            image = image_input.convert("RGB")
            
        tensor = self.transform(image).unsqueeze(0).to(self.device)
        with torch.no_grad():
            logits = self.model(tensor)
            probs = torch.softmax(logits[0], dim=0).cpu().numpy()
            
        pred_idx = int(probs.argmax())
        pred_category = self.idx_to_cat[pred_idx]
        confidence = float(probs[pred_idx])
        
        prob_dict = {
            self.idx_to_cat[i]: round(float(probs[i]), 4)
            for i in range(len(self.categories))
        }
        
        return {
            "predicted_category": pred_category,
            "confidence": round(confidence, 4),
            "probabilities": prob_dict
        }

if __name__ == "__main__":
    predictor = GAPEDInterestPredictor()
    sample_img = os.path.abspath("./data_prep/GAPED/categorized/animals/P073.jpg")
    if os.path.exists(sample_img):
        res = predictor.predict(sample_img)
        print("Sample prediction on animal image (P073.jpg):")
        print(json.dumps(res, indent=2))
