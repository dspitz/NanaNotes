# Ingredient Image Assets

This directory contains custom image assets for ingredients, providing a visual upgrade from emojis.

## Naming Convention

**Pattern:** `{normalizedName}.imageset`

- `normalizedName` = lowercase, spaces removed or replaced with underscores
- Examples:
  - `apple.imageset` → matches "apple", "Apple", "Apples"
  - `chicken_breast.imageset` → matches "chicken breast", "Chicken Breast"
  - `olive_oil.imageset` → matches "olive oil", "Olive Oil"

**Simple!** No "ingredient_" prefix needed since we're already in the Ingredients folder.

## Directory Structure

```
Ingredients/
├── Contents.json
├── README.md
├── apple.imageset/
├── banana.imageset/
├── milk.imageset/
├── chicken.imageset/
└── ... (all ingredients in flat list)
```

**Note:** All ingredient images live directly in the `Ingredients/` folder as a flat list. No "ingredient_" prefix, no category subfolders - just clean, simple names!

## Image Specifications

### Format
- **Preferred:** PNG with transparency
- **Alternative:** SVG (if supported by Xcode)

### Dimensions
- **1x:** 128x128 pixels
- **2x:** 256x256 pixels (recommended minimum)
- **3x:** 384x384 pixels (for optimal quality)

### Style Guide
- Flat, modern illustration style
- Simple, recognizable shapes
- Consistent color palette across all images
- No text or labels
- Transparent background
- Centered composition

## Priority List (Top 50 Items)

### Produce (15)
apple, banana, orange, lemon, lime, tomato, potato, carrot, onion, garlic, lettuce, cucumber, broccoli, avocado, strawberry

### Meat & Protein (10)
chicken, beef, pork, bacon, egg, salmon, shrimp, turkey, sausage, ground_beef

### Dairy (8)
milk, cheese, butter, yogurt, cream, sour_cream, ice_cream, almond_milk

### Pantry (10)
rice, pasta, bread, flour, sugar, salt, olive_oil, honey, peanut_butter, beans

### Beverages (4)
coffee, tea, juice, water

### Bakery (3)
bagel, croissant, muffin

## How to Add an Image

### Option 1: Using Xcode (Easiest)
1. Open `Assets.xcassets` in Xcode
2. Navigate to the `Ingredients` folder
3. Right-click → "New Image Set"
4. Name it `apple` (just the ingredient name)
5. Drag and drop your images into the 2x and/or 3x slots
6. Build and run - done!

### Option 2: Manually (with @2x/@3x for best quality)
1. Create a folder:
   ```
   Ingredients/apple.imageset/
   ```

2. Add your image files:
   ```
   apple@2x.png  (256x256)
   apple@3x.png  (384x384)
   ```

3. Create `Contents.json`:
   ```json
   {
     "images" : [
       {
         "filename" : "apple@2x.png",
         "idiom" : "universal",
         "scale" : "2x"
       },
       {
         "filename" : "apple@3x.png",
         "idiom" : "universal",
         "scale" : "3x"
       }
     ],
     "info" : {
       "author" : "xcode",
       "version" : 1
     }
   }
   ```

### Option 3: Manually (single image, simpler)
1. Create a folder:
   ```
   Ingredients/apple.imageset/
   ```

2. Add your image file (no @2x suffix needed):
   ```
   apple.png  (256x256 or larger)
   ```

3. Create `Contents.json`:
   ```json
   {
     "images" : [
       {
         "filename" : "apple.png",
         "idiom" : "universal",
         "scale" : "1x"
       }
     ],
     "info" : {
       "author" : "xcode",
       "version" : 1
     }
   }
   ```

**Note:** The @2x/@3x suffixes are optional. iOS uses them to pick the best resolution for each device. If you only provide one image, iOS will scale it automatically (still looks good!).

## Image Sources

- **Icon Libraries:** Noun Project, Flaticon, Icons8
- **Design Tools:** Figma, Illustrator, Sketch
- **Custom:** Commission from designer or AI generation

## Fallback Behavior

If an image is not found, the app gracefully falls back to the emoji system:
1. **First:** Try custom image asset (e.g., `apple`)
2. **Second:** Try custom image URL (future feature)
3. **Third:** Display emoji (always works)

This ensures the app never shows broken images or missing icons. You can add images gradually - items without images will just show emojis!
