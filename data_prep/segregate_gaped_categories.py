"""
Segregate Clean GAPED Images into Child-Friendly Interest Categories
--------------------------------------------------------------------
Divides the 210 clean images into 4 interest categories:
1. Animals (24 images): friendly pets, baby animals, wildlife (puppies, kittens, pandas, penguins)
2. Nature (48 images): scenic landscapes, mountains, beaches, forests, flowers, lakes
3. People (44 images): happy babies, toddlers, smiling children, joyful family activities
4. Objects (94 images): domestic furniture, tools, books, desks, kitchenware, bicycles

Outputs:
- Creates `data_prep/GAPED/categorized/<category>/` directory structure
- Saves optimized JPEG copies (and references original BMPs)
- Generates `data_prep/GAPED/gaped_interest_dataset.csv`
"""

import os
import shutil
import pandas as pd
from PIL import Image

def segregate_gaped(base_dir: str, output_dir: str, metadata_out_path: str):
    cleaned_meta_path = os.path.join(base_dir, "cleaned_dataset_metadata.csv")
    if not os.path.exists(cleaned_meta_path):
        raise FileNotFoundError(f"Cleaned metadata not found: {cleaned_meta_path}")
        
    df = pd.read_csv(cleaned_meta_path)
    
    # Ground truth category mappings
    animal_files = {
        'P046.bmp', 'P060.bmp', 'P066.bmp', 'P073.bmp', 'P074.bmp', 'P075.bmp',
        'P076.bmp', 'P077.bmp', 'P078.bmp', 'P079.bmp', 'P080.bmp', 'P081.bmp',
        'P082.bmp', 'P083.bmp', 'P094.bmp', 'P095.bmp', 'P096.bmp', 'P098.bmp',
        'P099.bmp', 'P100.bmp', 'P101.bmp', 'P113.bmp', 'P114.bmp', 'P122.bmp'
    }
    
    # P001 to P043 are babies & young children, plus outdoor people photos
    people_p_prefix = {f for f in df['filename'] if f.startswith('P') and int(f[1:4]) <= 43}
    people_files = people_p_prefix | {'P062.bmp', 'P090.bmp', 'P105.bmp', 'P129.bmp'}
    
    # In P: food/dessert/items
    p_object_files = {'P102.bmp', 'P103.bmp', 'P104.bmp', 'P111.bmp', 'P123.bmp'}
    # In N: all N001 to N111 are everyday objects
    n_object_files = {row['filename'] for _, row in df[df['category'] == 'N'].iterrows()}
    object_files = n_object_files | p_object_files
    
    # Nature is the remainder of P
    all_files = set(df['filename'])
    nature_files = all_files - animal_files - people_files - object_files
    
    category_map = {}
    for f in animal_files:
        category_map[f] = 'animals'
    for f in people_files:
        category_map[f] = 'people'
    for f in object_files:
        category_map[f] = 'objects'
    for f in nature_files:
        category_map[f] = 'nature'
        
    records = []
    for cat in ['animals', 'nature', 'people', 'objects']:
        os.makedirs(os.path.join(output_dir, cat), exist_ok=True)
        
    for _, row in df.iterrows():
        fn = row['filename']
        orig_cat = row['category']
        interest_cat = category_map[fn]
        
        src_path = os.path.join(base_dir, orig_cat, fn)
        dst_filename = f"{os.path.splitext(fn)[0]}.jpg"
        dst_path = os.path.join(output_dir, interest_cat, dst_filename)
        
        # Save high quality JPEG for UI & training
        with Image.open(src_path) as img:
            rgb_img = img.convert("RGB")
            rgb_img.save(dst_path, format="JPEG", quality=95)
            w, h = rgb_img.size
            
        records.append({
            'filename': fn,
            'image_id': os.path.splitext(fn)[0],
            'original_gaped_category': orig_cat,
            'interest_category': interest_cat,
            'image_path': dst_path,
            'original_bmp_path': src_path,
            'width': w,
            'height': h,
            'valence': row.get('valence', None),
            'arousal': row.get('arousal', None),
            'top3_preds': row.get('top3_preds', '')
        })
        
    out_df = pd.DataFrame(records)
    out_df.to_csv(metadata_out_path, index=False)
    print(f"Segregation complete! Saved {len(out_df)} records to {metadata_out_path}")
    print("\nClass breakdown:")
    print(out_df['interest_category'].value_counts())

if __name__ == "__main__":
    base_dir = os.path.abspath("./data_prep/GAPED/GAPED")
    output_dir = os.path.abspath("./data_prep/GAPED/categorized")
    meta_path = os.path.abspath("./data_prep/GAPED/gaped_interest_dataset.csv")
    segregate_gaped(base_dir, output_dir, meta_path)
