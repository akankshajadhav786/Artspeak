"""
Clean GAPED Dataset for Autistic Children (Ages 5 to 12)
-------------------------------------------------------
Removes inappropriate, distressing, and dangerous stimuli:
- Category A (124 images): Animal mistreatment, dead/slaughtered animals, cruelty.
- Category H (105 images): Human suffering, corpses, physical trauma, violence.
- Category Sn (133 images): Threatening/venomous snakes and reptiles (phobia-inducing).
- Category Sp (158 images): Hairy spiders, tarantulas, webs (phobia-inducing).

Retains only child-friendly, sensory-safe stimuli:
- Category N (89 images): Neutral domestic objects, furniture, architecture, everyday tools.
- Category P (121 images): Wholesome positive stimuli: puppies, kittens, baby animals, joyful scenes, nature.

Outputs:
- Removes inappropriate image folders and metadata text files.
- Generates a comprehensive cleaning manifest CSV documenting kept vs removed files and reasons.
- Generates unified clean metadata CSV for downstream training and inference.
"""

import os
import shutil
import pandas as pd

def clean_gaped(base_dir: str, output_manifest_path: str):
    # Correct path to audit file in data_prep directory
    audit_file = os.path.join(os.path.dirname(os.path.dirname(base_dir)), "gaped_audit_full.csv")
    if not os.path.exists(audit_file):
        audit_file = os.path.abspath("./data_prep/gaped_audit_full.csv")
    if not os.path.exists(audit_file):
        raise FileNotFoundError(f"Audit file not found: {audit_file}")
    
    df_audit = pd.read_csv(audit_file)
    
    # Categorize actions and reasons
    actions = []
    reasons = []
    
    removal_reasons = {
        "A": "REMOVED: Animal mistreatment, dead/slaughtered animals, cruelty, graphic wounds (unsuitable for children aged 5-12)",
        "H": "REMOVED: Human concern, corpses, starvation, violence, trauma (unsuitable for children aged 5-12)",
        "Sn": "REMOVED: Phobic/dangerous snake stimuli, striking postures, venomous reptiles (sensory threat for autistic children)",
        "Sp": "REMOVED: Phobic/dangerous spider stimuli, hairy tarantulas, webs (acute distress for autistic children)"
    }
    
    retention_reasons = {
        "N": "KEPT: Safe neutral domestic & environmental objects, furniture, tools, architecture (calm, child-friendly)",
        "P": "KEPT: Wholesome positive stimuli: baby animals, puppies, joyful children, peaceful nature scenery (nurturing, calming)"
    }
    
    for _, row in df_audit.iterrows():
        cat = row["category"]
        if cat in ["N", "P"]:
            actions.append("KEPT")
            reasons.append(retention_reasons[cat])
        else:
            actions.append("REMOVED")
            reasons.append(removal_reasons[cat])
            
    df_audit["status"] = actions
    df_audit["filter_rationale"] = reasons
    
    # Save full audit & cleaning manifest
    df_audit.to_csv(output_manifest_path, index=False)
    print(f"Saved full audit manifest to {output_manifest_path}")
    
    # Save cleaned subset metadata
    df_clean = df_audit[df_audit["status"] == "KEPT"].copy()
    clean_meta_path = os.path.join(base_dir, "cleaned_dataset_metadata.csv")
    df_clean.to_csv(clean_meta_path, index=False)
    print(f"Saved cleaned metadata ({len(df_clean)} images) to {clean_meta_path}")
    
    # Remove inappropriate directories
    inappropriate_cats = ["A", "H", "Sn", "Sp"]
    for cat in inappropriate_cats:
        cat_dir = os.path.join(base_dir, cat)
        if os.path.exists(cat_dir):
            shutil.rmtree(cat_dir)
            print(f"Deleted folder: {cat_dir}")
        
        # Remove corresponding text files
        for txt_name in [f"{cat}.txt", f"{cat}_with SD.txt"]:
            txt_path = os.path.join(base_dir, txt_name)
            if os.path.exists(txt_path):
                os.remove(txt_path)
                print(f"Deleted metadata text file: {txt_path}")
                
    # Clean DS_Store files
    for root, dirs, files in os.walk(os.path.dirname(base_dir)):
        for f in files:
            if f == ".DS_Store":
                try:
                    os.remove(os.path.join(root, f))
                except Exception:
                    pass

    print("\nDataset cleaning complete!")
    print(f"Total original images: {len(df_audit)}")
    print(f"Total removed images: {len(df_audit[df_audit['status'] == 'REMOVED'])}")
    print(f"Total kept child-friendly images: {len(df_clean)}")
    print("Breakdown of kept images:")
    print(df_clean["category"].value_counts())

if __name__ == "__main__":
    gaped_dir = os.path.abspath("./data_prep/GAPED/GAPED")
    manifest_path = os.path.abspath("./data_prep/gaped_cleaning_manifest.csv")
    clean_gaped(gaped_dir, manifest_path)
