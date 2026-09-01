import Foundation
import FoundationModels

/// The kinds of consumer spending a question can name, curated out of
/// mcc_codes.csv.
///
/// The model only ever picks cases off this list — guided generation constrains
/// it to these exact names — so it can never invent a category or misremember a
/// code. The step from a case to concrete MCC numbers is `codeRanges`,
/// deterministic Swift the prompt never sees. That split is what keeps 900-odd
/// codes' worth of knowledge affordable on a small on-device model: the model
/// does the semantic match ("food shopping" is groceries), the table does the
/// numbers.
@Generable(description: "A kind of consumer spending, such as groceries or flights.")
enum SpendingCategory: CaseIterable {
    // Travel and getting around
    case airlines
    case hotels
    case carRental
    case cruises
    case travelAgencies
    case publicTransit
    case taxiAndRideshare
    case parkingAndTolls
    case gasStations

    // Food and drink
    case groceries
    case restaurants
    case liquorStores

    // Shopping
    case departmentAndDiscountStores
    case clothing
    case electronics
    case furniture
    case homeImprovement
    case sportingGoods
    case toysAndHobbies
    case booksAndNews
    case jewelry
    case giftsAndFlowers

    // Home and services
    case utilities
    case phoneInternetAndCable
    case streamingAndDigitalGoods
    case insurance
    case financialServices
    case laundryAndDryCleaning
    case autoPartsAndService

    // Health and personal
    case pharmacies
    case healthcare
    case beautyAndSpa
    case gymsAndFitness
    case petsAndVets

    // Everything else a household pays for
    case entertainment
    case education
    case childcare
    case charity
    case government
}

extension SpendingCategory {
    /// The label the result card prints.
    var title: String {
        switch self {
        case .airlines: "Airlines"
        case .hotels: "Hotels & Lodging"
        case .carRental: "Car Rental"
        case .cruises: "Cruise Lines"
        case .travelAgencies: "Travel Agencies & Tours"
        case .publicTransit: "Public Transit"
        case .taxiAndRideshare: "Taxi & Rideshare"
        case .parkingAndTolls: "Parking & Tolls"
        case .gasStations: "Gas Stations"
        case .groceries: "Groceries"
        case .restaurants: "Restaurants & Bars"
        case .liquorStores: "Liquor Stores"
        case .departmentAndDiscountStores: "Department & Discount Stores"
        case .clothing: "Clothing & Apparel"
        case .electronics: "Electronics & Software"
        case .furniture: "Furniture & Home Furnishings"
        case .homeImprovement: "Home Improvement & Hardware"
        case .sportingGoods: "Sporting Goods & Bicycles"
        case .toysAndHobbies: "Toys & Hobbies"
        case .booksAndNews: "Books & Newsstands"
        case .jewelry: "Jewelry & Watches"
        case .giftsAndFlowers: "Gifts & Flowers"
        case .utilities: "Utilities"
        case .phoneInternetAndCable: "Phone, Internet & Cable"
        case .streamingAndDigitalGoods: "Streaming & Digital Goods"
        case .insurance: "Insurance"
        case .financialServices: "Financial Services"
        case .laundryAndDryCleaning: "Laundry & Dry Cleaning"
        case .autoPartsAndService: "Auto Parts & Service"
        case .pharmacies: "Pharmacies"
        case .healthcare: "Medical & Healthcare"
        case .beautyAndSpa: "Beauty & Spas"
        case .gymsAndFitness: "Gyms & Fitness"
        case .petsAndVets: "Pets & Veterinary"
        case .entertainment: "Entertainment & Attractions"
        case .education: "Education & Schools"
        case .childcare: "Childcare"
        case .charity: "Charity & Donations"
        case .government: "Government & Taxes"
        }
    }

    /// The MCC codes behind this category. A range covers every code
    /// mcc_codes.csv has between its bounds; brand-level blocks (one code per
    /// airline, hotel chain, or car-rental company) collapse into one range.
    var codeRanges: [ClosedRange<Int>] {
        switch self {
        case .airlines: [3000...3299, 4511...4511]
        case .hotels: [3500...3999, 7011...7011]
        case .carRental: [3300...3441, 7512...7519]
        case .cruises: [4411...4411]
        case .travelAgencies: [4722...4722]
        case .publicTransit: [4111...4112, 4131...4131]
        case .taxiAndRideshare: [4121...4121]
        case .parkingAndTolls: [4784...4784, 7523...7523]
        case .gasStations: [5541...5542]
        case .groceries: [5411...5499]
        case .restaurants: [5811...5814]
        case .liquorStores: [5921...5921]
        case .departmentAndDiscountStores: [5300...5399]
        case .clothing: [5611...5699]
        case .electronics: [5732...5732, 5734...5734]
        case .furniture: [5712...5722]
        case .homeImprovement: [5200...5261]
        case .sportingGoods: [5940...5941]
        case .toysAndHobbies: [5945...5945]
        case .booksAndNews: [5942...5942, 5994...5994]
        case .jewelry: [5944...5944]
        case .giftsAndFlowers: [5947...5947, 5992...5992]
        case .utilities: [4900...4900]
        case .phoneInternetAndCable: [4812...4816, 4899...4899]
        case .streamingAndDigitalGoods: [5815...5818]
        case .insurance: [6300...6300]
        case .financialServices: [6010...6051, 6211...6211]
        case .laundryAndDryCleaning: [7210...7216]
        case .autoPartsAndService: [5531...5533, 7531...7549]
        case .pharmacies: [5912...5912]
        case .healthcare: [4119...4119, 8011...8099]
        case .beautyAndSpa: [5977...5977, 7230...7230, 7298...7298]
        case .gymsAndFitness: [7941...7941, 7997...7997]
        case .petsAndVets: [742...742, 5995...5995]
        case .entertainment: [7832...7832, 7922...7922, 7991...7991, 7996...7996, 7998...7998]
        case .education: [8211...8299]
        case .childcare: [8351...8351]
        case .charity: [8398...8398]
        case .government: [9211...9402]
        }
    }

    /// The ranges the way the back-end takes them: "3000-3299", with a
    /// single-code range shortened to the bare code, "4511". MCCs are
    /// four digits, so 742 prints as "0742".
    var codeRangeStrings: [String] {
        codeRanges.map { range in
            range.lowerBound == range.upperBound
                ? String(format: "%04d", range.lowerBound)
                : String(format: "%04d-%04d", range.lowerBound, range.upperBound)
        }
    }

    /// One line for the result card: "Airlines (3000-3299, 4511)".
    var summary: String {
        "\(title) (\(codeRangeStrings.joined(separator: ", ")))"
    }
}

/// The list the category session fills in. Categories live in their own
/// session and their own generable so the taxonomy never crowds the
/// merchant-and-amount schema.
@Generable(description: "The kinds of spending a question about the user's own card transactions asks about.")
struct CategoryQuery: Equatable, Sendable {
    @Guide(
        description: #"Every kind of spending the question names, like "groceries" or "flights". Empty when it names none — a specific business such as "Starbucks" is not a kind of spending."#,
        .maximumCount(3)
    )
    var categories: [SpendingCategory]
}
