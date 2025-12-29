import Foundation
import SwiftData

actor CategorizationService {
    private let modelContext: ModelContext

    private let synonyms: [String: String] = [
        "scallion": "green onion",
        "scallions": "green onions",
        "cilantro": "coriander",
        "spring onion": "green onion",
        "romano": "romaine",
        "roma tomato": "tomato",
        "beefsteak tomato": "tomato"
    ]

    private let exactMatches: [String: GroceryCategory] = [
        // PRODUCE - FRUITS (50+ items)
        "apple": .produce, "apples": .produce, "granny smith apple": .produce, "honeycrisp apple": .produce, "gala apple": .produce,
        "banana": .produce, "bananas": .produce, "plantain": .produce, "plantains": .produce,
        "orange": .produce, "oranges": .produce, "mandarin": .produce, "mandarins": .produce, "clementine": .produce, "clementines": .produce, "tangerine": .produce, "tangerines": .produce,
        "lemon": .produce, "lemons": .produce, "lime": .produce, "limes": .produce,
        "berry": .produce, "berries": .produce, "strawberry": .produce, "strawberries": .produce, "blueberry": .produce, "blueberries": .produce, "raspberry": .produce, "raspberries": .produce, "blackberry": .produce, "blackberries": .produce, "cranberry": .produce, "cranberries": .produce, "mixed berries": .produce,
        "grape": .produce, "grapes": .produce, "green grapes": .produce, "red grapes": .produce,
        "watermelon": .produce, "cantaloupe": .produce, "honeydew": .produce, "melon": .produce,
        "pineapple": .produce, "mango": .produce, "mangos": .produce, "mangoes": .produce,
        "peach": .produce, "peaches": .produce, "nectarine": .produce, "nectarines": .produce,
        "pear": .produce, "pears": .produce, "plum": .produce, "plums": .produce,
        "cherry": .produce, "cherries": .produce, "kiwi": .produce, "kiwis": .produce,
        "papaya": .produce, "coconut": .produce, "coconuts": .produce, "avocado": .produce, "avocados": .produce,
        "pomegranate": .produce, "pomegranates": .produce, "fig": .produce, "figs": .produce,
        "apricot": .produce, "apricots": .produce, "grapefruit": .produce, "grapefruits": .produce,
        "dragon fruit": .produce, "star fruit": .produce, "passion fruit": .produce,
        "persimmon": .produce, "persimmons": .produce, "guava": .produce,

        // PRODUCE - VEGETABLES (80+ items)
        "lettuce": .produce, "romaine lettuce": .produce, "iceberg lettuce": .produce, "butter lettuce": .produce, "arugula": .produce, "mixed greens": .produce, "salad mix": .produce,
        "tomato": .produce, "tomatoes": .produce, "cherry tomatoes": .produce, "grape tomatoes": .produce, "roma tomatoes": .produce, "beefsteak tomato": .produce, "heirloom tomato": .produce,
        "onion": .produce, "onions": .produce, "red onion": .produce, "yellow onion": .produce, "white onion": .produce, "sweet onion": .produce, "vidalia onion": .produce,
        "green onion": .produce, "green onions": .produce, "scallion": .produce, "scallions": .produce, "spring onion": .produce, "leek": .produce, "leeks": .produce, "shallot": .produce, "shallots": .produce,
        "potato": .produce, "potatoes": .produce, "russet potato": .produce, "red potato": .produce, "yukon gold potato": .produce, "sweet potato": .produce, "sweet potatoes": .produce, "yam": .produce, "yams": .produce,
        "carrot": .produce, "carrots": .produce, "baby carrots": .produce,
        "cucumber": .produce, "cucumbers": .produce, "english cucumber": .produce, "persian cucumber": .produce,
        "bell pepper": .produce, "red bell pepper": .produce, "green bell pepper": .produce, "yellow bell pepper": .produce, "orange bell pepper": .produce,
        "pepper": .produce, "peppers": .produce, "jalapeño": .produce, "jalapeños": .produce, "serrano pepper": .produce, "poblano pepper": .produce, "habanero": .produce,
        "spinach": .produce, "baby spinach": .produce, "broccoli": .produce, "cauliflower": .produce,
        "garlic": .produce, "garlic cloves": .produce, "ginger": .produce, "fresh ginger": .produce, "ginger root": .produce,
        "mushroom": .produce, "mushrooms": .produce, "white mushrooms": .produce, "cremini mushrooms": .produce, "portobello mushrooms": .produce, "shiitake mushrooms": .produce,
        "celery": .produce, "kale": .produce, "zucchini": .produce, "squash": .produce, "yellow squash": .produce, "butternut squash": .produce, "acorn squash": .produce, "spaghetti squash": .produce,
        "eggplant": .produce, "cabbage": .produce, "green cabbage": .produce, "red cabbage": .produce, "napa cabbage": .produce, "bok choy": .produce,
        "asparagus": .produce, "green beans": .produce, "snap peas": .produce, "snow peas": .produce, "peas": .produce,
        "corn": .produce, "corn on the cob": .produce, "beet": .produce, "beets": .produce, "radish": .produce, "radishes": .produce,
        "brussels sprouts": .produce, "artichoke": .produce, "artichokes": .produce,
        "parsley": .produce, "cilantro": .produce, "coriander": .produce, "basil": .produce, "fresh basil": .produce, "mint": .produce, "fresh mint": .produce, "dill": .produce, "thyme": .produce, "rosemary": .produce,

        // MEAT & SEAFOOD (60+ items)
        "chicken": .meat, "chicken breast": .meat, "chicken breasts": .meat, "boneless chicken breast": .meat, "chicken thighs": .meat, "chicken thigh": .meat, "chicken drumsticks": .meat, "chicken wings": .meat, "whole chicken": .meat, "rotisserie chicken": .meat,
        "ground beef": .meat, "beef": .meat, "steak": .meat, "ribeye": .meat, "ribeye steak": .meat, "sirloin": .meat, "sirloin steak": .meat, "filet mignon": .meat, "new york strip": .meat, "t-bone steak": .meat,
        "ground turkey": .meat, "turkey": .meat, "turkey breast": .meat, "deli turkey": .meat, "sliced turkey": .meat,
        "pork": .meat, "pork chops": .meat, "pork tenderloin": .meat, "pork ribs": .meat, "pork shoulder": .meat, "pulled pork": .meat,
        "bacon": .meat, "turkey bacon": .meat, "canadian bacon": .meat,
        "sausage": .meat, "sausages": .meat, "italian sausage": .meat, "breakfast sausage": .meat, "chorizo": .meat, "bratwurst": .meat, "kielbasa": .meat, "hot dogs": .meat, "hot dog": .meat,
        "ham": .meat, "deli ham": .meat, "prosciutto": .meat, "salami": .meat, "pepperoni": .meat, "pastrami": .meat,
        "lamb": .meat, "lamb chops": .meat, "leg of lamb": .meat,
        "salmon": .meat, "salmon fillet": .meat, "smoked salmon": .meat, "lox": .meat,
        "tuna": .meat, "tuna steak": .meat, "canned tuna": .pantry, "tuna can": .pantry,
        "shrimp": .meat, "prawns": .meat, "scallops": .meat, "crab": .meat, "crab legs": .meat, "lobster": .meat, "lobster tail": .meat,
        "tilapia": .meat, "cod": .meat, "halibut": .meat, "mahi mahi": .meat, "sea bass": .meat, "swordfish": .meat, "trout": .meat,
        "fish": .meat, "white fish": .meat, "fish fillet": .meat,

        // DAIRY & EGGS (50+ items)
        "milk": .dairy, "whole milk": .dairy, "2% milk": .dairy, "skim milk": .dairy, "1% milk": .dairy, "fat free milk": .dairy,
        "almond milk": .dairy, "oat milk": .dairy, "soy milk": .dairy, "coconut milk": .dairy, "cashew milk": .dairy, "rice milk": .dairy,
        "half and half": .dairy, "heavy cream": .dairy, "heavy whipping cream": .dairy, "whipping cream": .dairy, "light cream": .dairy,
        "sour cream": .dairy, "cream cheese": .dairy, "whipped cream": .dairy, "cool whip": .dairy,
        "butter": .dairy, "salted butter": .dairy, "unsalted butter": .dairy, "margarine": .dairy,
        "yogurt": .dairy, "greek yogurt": .dairy, "plain yogurt": .dairy, "vanilla yogurt": .dairy, "strawberry yogurt": .dairy,
        "cottage cheese": .dairy, "ricotta cheese": .dairy, "mascarpone": .dairy,
        "cheese": .dairy, "cheddar cheese": .dairy, "mozzarella": .dairy, "mozzarella cheese": .dairy, "parmesan": .dairy, "parmesan cheese": .dairy, "swiss cheese": .dairy, "american cheese": .dairy, "provolone": .dairy, "monterey jack": .dairy,
        "feta cheese": .dairy, "goat cheese": .dairy, "brie": .dairy, "blue cheese": .dairy, "gorgonzola": .dairy,
        "string cheese": .dairy, "cheese sticks": .dairy, "babybel": .dairy, "laughing cow": .dairy,
        "egg": .dairy, "eggs": .dairy, "brown eggs": .dairy, "white eggs": .dairy, "free range eggs": .dairy, "organic eggs": .dairy, "egg whites": .dairy,

        // BAKERY (40+ items)
        "bread": .bakery, "white bread": .bakery, "wheat bread": .bakery, "whole wheat bread": .bakery, "sourdough": .bakery, "sourdough bread": .bakery, "rye bread": .bakery, "pumpernickel": .bakery, "french bread": .bakery, "italian bread": .bakery,
        "bagel": .bakery, "bagels": .bakery, "plain bagel": .bakery, "everything bagel": .bakery, "sesame bagel": .bakery,
        "roll": .bakery, "rolls": .bakery, "dinner rolls": .bakery, "kaiser roll": .bakery, "ciabatta": .bakery, "ciabatta roll": .bakery,
        "bun": .bakery, "buns": .bakery, "hamburger buns": .bakery, "hot dog buns": .bakery, "brioche buns": .bakery,
        "tortilla": .bakery, "tortillas": .bakery, "flour tortillas": .bakery, "corn tortillas": .bakery, "wrap": .bakery, "wraps": .bakery,
        "pita": .bakery, "pita bread": .bakery, "naan": .bakery, "flatbread": .bakery,
        "croissant": .bakery, "croissants": .bakery, "muffin": .bakery, "muffins": .bakery, "blueberry muffin": .bakery, "bran muffin": .bakery,
        "donut": .bakery, "donuts": .bakery, "doughnuts": .bakery, "danish": .bakery, "cinnamon roll": .bakery, "cinnamon rolls": .bakery,
        "cake": .bakery, "cupcake": .bakery, "cupcakes": .bakery, "pie": .bakery, "cookie": .bakery, "cookies": .bakery,

        // PANTRY (100+ items)
        "rice": .pantry, "white rice": .pantry, "brown rice": .pantry, "jasmine rice": .pantry, "basmati rice": .pantry, "arborio rice": .pantry, "wild rice": .pantry,
        "pasta": .pantry, "spaghetti": .pantry, "penne": .pantry, "fettuccine": .pantry, "linguine": .pantry, "rigatoni": .pantry, "macaroni": .pantry, "elbow macaroni": .pantry,
        "mac and cheese": .pantry, "macaroni and cheese": .pantry, "kraft dinner": .pantry, "boxed mac and cheese": .pantry,
        "noodles": .pantry, "egg noodles": .pantry, "ramen": .pantry, "ramen noodles": .pantry, "instant noodles": .pantry, "rice noodles": .pantry, "pad thai noodles": .pantry,
        "flour": .pantry, "all purpose flour": .pantry, "bread flour": .pantry, "cake flour": .pantry, "whole wheat flour": .pantry,
        "sugar": .pantry, "white sugar": .pantry, "granulated sugar": .pantry, "brown sugar": .pantry, "powdered sugar": .pantry, "confectioners sugar": .pantry, "cane sugar": .pantry,
        "oil": .pantry, "olive oil": .pantry, "vegetable oil": .pantry, "canola oil": .pantry, "coconut oil": .pantry, "sesame oil": .pantry, "avocado oil": .pantry,
        "cooking spray": .pantry, "pam": .pantry,
        "salt": .pantry, "table salt": .pantry, "sea salt": .pantry, "kosher salt": .pantry, "himalayan salt": .pantry,
        "black pepper": .pantry, "ground black pepper": .pantry, "white pepper": .pantry, "peppercorn": .pantry,
        "cereal": .pantry, "cheerios": .pantry, "corn flakes": .pantry, "frosted flakes": .pantry, "fruit loops": .pantry, "rice krispies": .pantry, "oatmeal": .pantry, "oats": .pantry, "rolled oats": .pantry, "quick oats": .pantry, "instant oatmeal": .pantry,
        "granola": .pantry, "granola bar": .pantry, "granola bars": .pantry,
        "beans": .pantry, "black beans": .pantry, "kidney beans": .pantry, "pinto beans": .pantry, "chickpeas": .pantry, "garbanzo beans": .pantry, "lentils": .pantry, "split peas": .pantry,
        "canned beans": .pantry, "refried beans": .pantry, "baked beans": .pantry,
        "quinoa": .pantry, "couscous": .pantry, "bulgur": .pantry, "barley": .pantry, "farro": .pantry,
        "tomato sauce": .pantry, "marinara sauce": .pantry, "pasta sauce": .pantry, "spaghetti sauce": .pantry, "alfredo sauce": .pantry,
        "ketchup": .pantry, "mustard": .pantry, "yellow mustard": .pantry, "dijon mustard": .pantry, "mayo": .pantry, "mayonnaise": .pantry, "miracle whip": .pantry,
        "hot sauce": .pantry, "sriracha": .pantry, "tabasco": .pantry, "bbq sauce": .pantry, "barbecue sauce": .pantry,
        "soy sauce": .pantry, "teriyaki sauce": .pantry, "worcestershire sauce": .pantry, "fish sauce": .pantry, "oyster sauce": .pantry, "hoisin sauce": .pantry,
        "salsa": .pantry, "pico de gallo": .pantry, "guacamole": .pantry, "hummus": .pantry,
        "peanut butter": .pantry, "almond butter": .pantry, "nutella": .pantry, "jam": .pantry, "jelly": .pantry, "preserves": .pantry, "strawberry jam": .pantry, "grape jelly": .pantry,
        "honey": .pantry, "maple syrup": .pantry, "agave": .pantry, "agave nectar": .pantry, "molasses": .pantry,
        "vinegar": .pantry, "white vinegar": .pantry, "apple cider vinegar": .pantry, "balsamic vinegar": .pantry, "red wine vinegar": .pantry, "rice vinegar": .pantry,
        "canned tomatoes": .pantry, "diced tomatoes": .pantry, "crushed tomatoes": .pantry, "tomato paste": .pantry, "tomato soup": .pantry,
        "chicken broth": .pantry, "beef broth": .pantry, "vegetable broth": .pantry, "chicken stock": .pantry, "beef stock": .pantry, "vegetable stock": .pantry,
        "soup": .pantry, "canned soup": .pantry, "campbell's soup": .pantry,
        "crackers": .pantry, "saltines": .pantry, "ritz crackers": .pantry, "graham crackers": .pantry, "goldfish": .pantry,
        "chips": .pantry, "potato chips": .pantry, "lays": .pantry, "doritos": .pantry, "tortilla chips": .pantry, "pringles": .pantry, "cheetos": .pantry,
        "popcorn": .pantry, "microwave popcorn": .pantry, "pretzels": .pantry,
        "nuts": .pantry, "peanuts": .pantry, "almonds": .pantry, "cashews": .pantry, "walnuts": .pantry, "pecans": .pantry, "pistachios": .pantry, "mixed nuts": .pantry,
        "baking powder": .pantry, "baking soda": .pantry, "yeast": .pantry, "vanilla extract": .pantry, "vanilla": .pantry, "almond extract": .pantry,
        "chocolate chips": .pantry, "cocoa powder": .pantry, "cornstarch": .pantry, "corn meal": .pantry,
        "cinnamon": .pantry, "paprika": .pantry, "cumin": .pantry, "dried oregano": .pantry, "dried basil": .pantry, "garlic powder": .pantry, "onion powder": .pantry, "chili powder": .pantry, "cayenne pepper": .pantry, "red pepper flakes": .pantry,
        "italian seasoning": .pantry, "taco seasoning": .pantry, "ranch seasoning": .pantry,

        // FROZEN (30+ items)
        "ice cream": .frozen, "vanilla ice cream": .frozen, "chocolate ice cream": .frozen, "strawberry ice cream": .frozen, "gelato": .frozen, "sorbet": .frozen, "sherbet": .frozen,
        "frozen pizza": .frozen, "frozen vegetables": .frozen, "frozen fruit": .frozen, "frozen berries": .frozen, "frozen broccoli": .frozen, "frozen peas": .frozen, "frozen corn": .frozen,
        "popsicle": .frozen, "popsicles": .frozen, "ice pops": .frozen, "frozen yogurt": .frozen,
        "frozen dinner": .frozen, "tv dinner": .frozen, "lean cuisine": .frozen, "hungry man": .frozen,
        "frozen french fries": .frozen, "french fries": .frozen, "fries": .frozen, "tater tots": .frozen, "hash browns": .frozen,
        "frozen chicken nuggets": .frozen, "chicken nuggets": .frozen, "frozen fish sticks": .frozen, "fish sticks": .frozen,
        "frozen waffles": .frozen, "eggo waffles": .frozen, "frozen pancakes": .frozen,
        "ice": .frozen, "ice cubes": .frozen, "bag of ice": .frozen,

        // BEVERAGES (50+ items)
        "water": .beverages, "bottled water": .beverages, "sparkling water": .beverages, "seltzer": .beverages, "la croix": .beverages, "perrier": .beverages, "san pellegrino": .beverages,
        "orange juice": .beverages, "oj": .beverages, "apple juice": .beverages, "grape juice": .beverages, "cranberry juice": .beverages, "grapefruit juice": .beverages, "pineapple juice": .beverages,
        "juice": .beverages, "fruit juice": .beverages, "lemonade": .beverages, "limeade": .beverages,
        "soda": .beverages, "pop": .beverages, "coke": .beverages, "coca cola": .beverages, "pepsi": .beverages, "sprite": .beverages, "7up": .beverages, "mountain dew": .beverages, "dr pepper": .beverages, "root beer": .beverages, "ginger ale": .beverages,
        "diet coke": .beverages, "diet pepsi": .beverages, "coke zero": .beverages,
        "iced tea": .beverages, "sweet tea": .beverages, "unsweetened tea": .beverages, "arizona tea": .beverages, "snapple": .beverages,
        "energy drink": .beverages, "red bull": .beverages, "monster": .beverages, "gatorade": .beverages, "powerade": .beverages,
        "coffee": .beverages, "ground coffee": .beverages, "coffee beans": .beverages, "instant coffee": .beverages, "espresso": .beverages, "k cups": .beverages, "coffee pods": .beverages,
        "tea": .beverages, "tea bags": .beverages, "green tea": .beverages, "black tea": .beverages, "herbal tea": .beverages, "chamomile tea": .beverages,
        "hot chocolate": .beverages, "cocoa": .beverages, "chocolate milk": .beverages,
        "beer": .beverages, "wine": .beverages, "red wine": .beverages, "white wine": .beverages, "champagne": .beverages, "prosecco": .beverages,
        "vodka": .beverages, "gin": .beverages, "rum": .beverages, "tequila": .beverages, "whiskey": .beverages, "bourbon": .beverages,

        // HOUSEHOLD (40+ items)
        "paper towel": .household, "paper towels": .household, "bounty": .household,
        "toilet paper": .household, "tp": .household, "charmin": .household,
        "napkins": .household, "paper napkins": .household,
        "trash bag": .household, "trash bags": .household, "garbage bags": .household, "kitchen bags": .household, "hefty bags": .household, "glad bags": .household,
        "dish soap": .household, "dishwashing liquid": .household, "dawn": .household,
        "hand soap": .household, "bar soap": .household, "body wash": .household, "dove soap": .household,
        "laundry detergent": .household, "tide": .household, "gain": .household, "fabric softener": .household, "dryer sheets": .household, "bounce": .household,
        "bleach": .household, "clorox": .household, "disinfectant": .household, "lysol": .household,
        "cleaning spray": .household, "all purpose cleaner": .household, "windex": .household, "glass cleaner": .household,
        "sponge": .household, "sponges": .household, "scrub brush": .household,
        "aluminum foil": .household, "foil": .household, "plastic wrap": .household, "saran wrap": .household, "cling wrap": .household,
        "ziploc bags": .household, "sandwich bags": .household, "storage bags": .household, "freezer bags": .household,
        "parchment paper": .household, "wax paper": .household,
        "batteries": .household, "aa batteries": .household, "aaa batteries": .household, "light bulbs": .household
    ]

    private let categoryKeywords: [String: GroceryCategory] = [
        // Fruits
        "apple": .produce, "banana": .produce, "orange": .produce, "lemon": .produce, "lime": .produce,
        "strawberry": .produce, "blueberry": .produce, "raspberry": .produce, "blackberry": .produce,
        "grape": .produce, "watermelon": .produce, "melon": .produce, "pineapple": .produce,
        "mango": .produce, "peach": .produce, "pear": .produce, "plum": .produce, "cherry": .produce,
        "kiwi": .produce, "papaya": .produce, "coconut": .produce, "avocado": .produce,

        // Vegetables
        "lettuce": .produce, "tomato": .produce, "onion": .produce, "potato": .produce,
        "carrot": .produce, "cucumber": .produce, "bell pepper": .produce, "pepper": .produce,
        "spinach": .produce, "broccoli": .produce, "garlic": .produce, "ginger": .produce,
        "mushroom": .produce, "celery": .produce, "kale": .produce, "zucchini": .produce,
        "eggplant": .produce, "squash": .produce, "cabbage": .produce, "cauliflower": .produce,

        "bread": .bakery, "bagel": .bakery, "roll": .bakery, "bun": .bakery,
        "croissant": .bakery, "muffin": .bakery, "donut": .bakery, "tortilla": .bakery,

        "chicken": .meat, "beef": .meat, "pork": .meat, "turkey": .meat,
        "salmon": .meat, "fish": .meat, "shrimp": .meat, "bacon": .meat,
        "sausage": .meat, "ground": .meat, "steak": .meat, "lamb": .meat,

        "milk": .dairy, "yogurt": .dairy, "butter": .dairy,
        "cream": .dairy, "egg": .dairy, "eggs": .dairy,

        "rice": .pantry, "pasta": .pantry, "noodle": .pantry, "macaroni": .pantry,
        "flour": .pantry, "sugar": .pantry, "oil": .pantry, "salt": .pantry,
        "cereal": .pantry, "oats": .pantry, "beans": .pantry,
        "sauce": .pantry, "vinegar": .pantry, "spice": .pantry, "can": .pantry, "canned": .pantry,

        "frozen": .frozen,

        "water": .beverages, "juice": .beverages, "soda": .beverages, "beer": .beverages,
        "wine": .beverages, "coffee": .beverages, "tea": .beverages,

        "soap": .household, "detergent": .household, "cleaner": .household,
        "sponge": .household, "bleach": .household
    ]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func normalizeItemName(_ name: String) -> String {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return synonyms[normalized] ?? normalized
    }

    // Fast batch categorization for multiple items (processes all at once, no per-item async overhead)
    func batchCategorize(_ items: [(name: String, quantity: String?)]) async throws -> [(name: String, normalized: String, quantity: String?, category: GroceryCategory, knowledge: ItemKnowledge?)] {
        var results: [(name: String, normalized: String, quantity: String?, category: GroceryCategory, knowledge: ItemKnowledge?)] = []

        for item in items {
            let normalized = normalizeItemName(item.name)
            let (category, knowledge) = try await categorizeItem(item.name)
            results.append((item.name, normalized, item.quantity, category, knowledge))
        }

        return results
    }

    func categorizeItem(_ itemName: String) async throws -> (category: GroceryCategory, knowledge: ItemKnowledge?) {
        let normalized = normalizeItemName(itemName)
        let normalizedCopy = normalized

        let descriptor = FetchDescriptor<ItemKnowledge>(
            predicate: #Predicate<ItemKnowledge> { item in
                item.normalizedName == normalizedCopy
            }
        )
        let existingKnowledge = try? modelContext.fetch(descriptor).first

        if let knowledge = existingKnowledge {
            return (knowledge.categoryDefault, knowledge)
        }

        if let exactCategory = exactMatches[normalized] {
            return (exactCategory, nil)
        }

        let words = normalized.split(separator: " ").map(String.init)

        for word in words {
            if let category = exactMatches[word] {
                return (category, nil)
            }
        }

        for (keyword, category) in categoryKeywords.sorted(by: { $0.key.count > $1.key.count }) {
            if words.contains(keyword) {
                return (category, nil)
            }
        }

        for (keyword, category) in categoryKeywords.sorted(by: { $0.key.count > $1.key.count }) {
            if normalized.contains(keyword) {
                return (category, nil)
            }
        }

        return (.other, nil)
    }

    func enrichItemWithKnowledge(_ item: GroceryItem) async throws {
        let itemNormalizedName = item.normalizedName

        let descriptor = FetchDescriptor<ItemKnowledge>(
            predicate: #Predicate<ItemKnowledge> { knowledge in
                knowledge.normalizedName == itemNormalizedName
            }
        )

        if let knowledge = try? modelContext.fetch(descriptor).first {
            item.category = knowledge.categoryDefault
            item.storageAdvice = knowledge.storageAdvice
            item.shelfLifeDaysMin = knowledge.shelfLifeDaysMin
            item.shelfLifeDaysMax = knowledge.shelfLifeDaysMax
            item.shelfLifeSource = knowledge.source
            item.updatedAt = Date()
        }
    }

    func saveKnowledge(
        normalizedName: String,
        category: GroceryCategory,
        storageAdvice: String?,
        shelfLifeDaysMin: Int?,
        shelfLifeDaysMax: Int?,
        source: String
    ) async throws {
        let nameToFind = normalizedName

        let descriptor = FetchDescriptor<ItemKnowledge>(
            predicate: #Predicate<ItemKnowledge> { knowledge in
                knowledge.normalizedName == nameToFind
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.categoryDefaultRaw = category.rawValue
            existing.storageAdvice = storageAdvice
            existing.shelfLifeDaysMin = shelfLifeDaysMin
            existing.shelfLifeDaysMax = shelfLifeDaysMax
            existing.source = source
            existing.updatedAt = Date()
        } else {
            let knowledge = ItemKnowledge(
                normalizedName: normalizedName,
                categoryDefault: category,
                storageAdvice: storageAdvice,
                shelfLifeDaysMin: shelfLifeDaysMin,
                shelfLifeDaysMax: shelfLifeDaysMax,
                source: source
            )
            modelContext.insert(knowledge)
        }

        try modelContext.save()
    }
}
