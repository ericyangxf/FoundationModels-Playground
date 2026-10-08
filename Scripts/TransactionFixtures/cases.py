"""The 100 Transactions-tab questions, written the way a bank client types them.

Each case: (swift_name, question, scope, check)
  scope: dict(merchant=, categories=[...], min=, max=, dates=(from, to) | None)
  check: one of
    ("total",)             total of the matching set
    ("count",)             number of matching transactions
    ("average",)           average of the matching set
    ("largest",)           largest transaction: merchant + amount
    ("smallest",)          smallest transaction: merchant + amount
    ("latest",)            most recent transaction: date
    ("latestAmount",)      most recent transaction: date + amount
    ("earliest",)          earliest transaction: date
    ("list", order, n)     the first n in that order: every amount (or date) shown
    ("listDates",)         every matching transaction's date
    ("group", by, name)    a named group's total in a breakdown (name None = top)
    ("nothing",)           no transactions match; the answer must say so
Dates are inclusive, against an as-of date of Tuesday 2026-10-06.
"""

TODAY = "2026-10-06"
THIS_YEAR = ("2026-01-01", "2026-12-31")
LAST_MONTH = ("2026-09-01", "2026-09-30")
THIS_MONTH = ("2026-10-01", "2026-10-31")
PAST_6_MONTHS = ("2026-04-06", TODAY)
PAST_3_MONTHS = ("2026-07-06", TODAY)
PAST_2_MONTHS = ("2026-08-06", TODAY)
PAST_YEAR = ("2025-10-06", TODAY)
SINCE_JUNE = ("2026-06-01", TODAY)
SINCE_JANUARY = ("2026-01-01", TODAY)


def s(merchant=None, categories=(), min=None, max=None, dates=None):
    return dict(merchant=merchant, categories=list(categories), min=min, max=max, dates=dates)


CASES = [
    # --- How much at a merchant ------------------------------------------
    ("uberPastSixMonths", "How much I spent at Uber in the past 6 months",
     s("Uber", dates=PAST_6_MONTHS), ("total",)),
    ("uberSoFarThisYear", "how much have i spent on uber so far this year",
     s("Uber", dates=THIS_YEAR), ("total",)),
    ("timHortonsLastMonth", "What's my total at Tim Hortons last month?",
     s("Tim Hortons", dates=LAST_MONTH), ("total",)),
    ("starbucksDamageThisYear", "Starbucks damage for this year?",
     s("Starbucks", dates=THIS_YEAR), ("total",)),
    ("lcboSinceJune", "How much did I drop at the LCBO since June?",
     s("LCBO", dates=SINCE_JUNE), ("total",)),
    ("costcoLastThreeMonths", "Total spent at Costco in the last 3 months",
     s("Costco", dates=PAST_3_MONTHS), ("total",)),
    ("amazonIn2025", "How much went to Amazon in 2025?",
     s("Amazon", dates=("2025-01-01", "2025-12-31")), ("total",)),
    ("rogersThisYear", "How much have I paid Rogers this year?",
     s("Rogers", dates=THIS_YEAR), ("total",)),
    ("netflixPastYear", "What has Netflix cost me over the past year?",
     s("Netflix", dates=PAST_YEAR), ("total",)),
    ("loblawsLast90Days", "How much have I spent at Loblaws in the last 90 days?",
     s("Loblaws", dates=("2026-07-08", TODAY)), ("total",)),
    ("shoppersInMarch", "What did I spend at Shoppers Drug Mart in March?",
     s("Shoppers Drug Mart", dates=("2026-03-01", "2026-03-31")), ("total",)),
    ("canadianTireSinceStartOfYear", "Canadian Tire spending since the start of the year",
     s("Canadian Tire", dates=SINCE_JANUARY), ("total",)),
    ("petroCanadaLastMonth", "How much did I put into Petro-Canada last month?",
     s("Petro-Canada", dates=LAST_MONTH), ("total",)),
    ("goodLifeSoFarThisYear", "What have I paid GoodLife so far this year?",
     s("GoodLife Fitness", dates=THIS_YEAR), ("total",)),
    ("doorDashPastTwoMonths", "How much have I blown on DoorDash in the past 2 months?",
     s("DoorDash", dates=PAST_2_MONTHS), ("total",)),
    ("ikeaAllTime", "How much have I spent at IKEA?",
     s("IKEA"), ("total",)),
    ("airCanadaInFebruary", "What did my Air Canada flights cost in February?",
     s("Air Canada", dates=("2026-02-01", "2026-02-28")), ("total",)),
    ("homeDepotAprilToJune", "How much did I spend at Home Depot between April and June?",
     s("Home Depot", dates=("2026-04-01", "2026-06-30")), ("total",)),

    # --- How many ---------------------------------------------------------
    ("timHortonsVisitsPastThreeMonths", "How many times did I go to Tim Hortons in the past 3 months?",
     s("Tim Hortons", dates=PAST_3_MONTHS), ("count",)),
    ("uberRidesLastMonth", "How many Uber rides did I take last month?",
     s("Uber", dates=LAST_MONTH), ("count",)),
    ("starbucksVisitsThisYear", "How many times did I hit up Starbucks this year?",
     s("Starbucks", dates=THIS_YEAR), ("count",)),
    ("petroCanadaFillUpsSinceJanuary", "How many times did I fill up at Petro-Canada since January?",
     s("Petro-Canada", dates=SINCE_JANUARY), ("count",)),
    ("amazonOrdersPastSixMonths", "How many Amazon orders did I place in the past 6 months?",
     s("Amazon", dates=PAST_6_MONTHS), ("count",)),
    ("eatingOutLastMonth", "How many times did I eat out last month?",
     s(categories=["restaurants"], dates=LAST_MONTH), ("count",)),
    ("groceryRunsInSeptember", "How many grocery runs did I make in September?",
     s(categories=["groceries"], dates=("2026-09-01", "2026-09-30")), ("count",)),
    ("purchasesYesterday", "How many purchases did I make yesterday?",
     s(dates=("2026-10-05", "2026-10-05")), ("count",)),
    ("chargesOverHundredLastMonth", "How many charges over $100 did I have last month?",
     s(min=100, dates=LAST_MONTH), ("count",)),
    ("netflixChargesThisYear", "How many times has Netflix charged me this year?",
     s("Netflix", dates=THIS_YEAR), ("count",)),
    ("netflixTwiceInAugust", "Did Netflix charge me twice in August?",
     s("Netflix", dates=("2026-08-01", "2026-08-31")), ("count",)),

    # --- How much on a kind of spending ----------------------------------
    ("groceriesLastMonth", "How much did I spend on groceries last month?",
     s(categories=["groceries"], dates=LAST_MONTH), ("total",)),
    ("gasThisYear", "How much have I spent on gas this year?",
     s(categories=["gasStations"], dates=THIS_YEAR), ("total",)),
    ("eatingOutPastThirtyDays", "What did I spend eating out in the past 30 days?",
     s(categories=["restaurants"], dates=("2026-09-06", TODAY)), ("total",)),
    ("ridesLastMonth", "How much did I spend on rides last month?",
     s(categories=["taxiAndRideshare"], dates=LAST_MONTH), ("total",)),
    ("flightsThisYear", "How much have I spent on flights this year?",
     s(categories=["airlines"], dates=THIS_YEAR), ("total",)),
    ("phoneBillPastSixMonths", "What's my phone bill total for the past 6 months?",
     s(categories=["phoneInternetAndCable"], dates=PAST_6_MONTHS), ("total",)),
    ("alcoholSinceJune", "How much have I spent on alcohol since June?",
     s(categories=["liquorStores"], dates=SINCE_JUNE), ("total",)),
    ("pharmacyLastThreeMonths", "Pharmacy spending in the last 3 months?",
     s(categories=["pharmacies"], dates=PAST_3_MONTHS), ("total",)),
    ("streamingThisYear", "How much am I paying for streaming this year?",
     s(categories=["streamingAndDigitalGoods"], dates=THIS_YEAR), ("total",)),
    ("publicTransitThisYear", "How much did I spend on public transit this year?",
     s(categories=["publicTransit"], dates=THIS_YEAR), ("total",)),
    ("hotelsPastYear", "How much did hotels cost me in the past year?",
     s(categories=["hotels"], dates=PAST_YEAR), ("total",)),
    ("parkingAllTime", "How much have I spent on parking?",
     s(categories=["parkingAndTolls"]), ("total",)),
    ("petThisYear", "How much did my pet cost me this year?",
     s(categories=["petsAndVets"], dates=THIS_YEAR), ("total",)),
    ("electronicsAllTime", "How much did I spend on electronics?",
     s(categories=["electronics"]), ("total",)),
    ("clothesSinceJanuary", "How much did I spend on clothes since January?",
     s(categories=["clothing"], dates=SINCE_JANUARY), ("total",)),
    ("furnitureAndHomeImprovementThisYear", "Furniture and home improvement spending this year",
     s(categories=["furniture", "homeImprovement"], dates=THIS_YEAR), ("total",)),

    # --- Amount filters ---------------------------------------------------
    ("everyPurchaseOverFiveHundred", "Show me every purchase over $500",
     s(min=500), ("list", "largest", 10)),
    ("chargesAboveThreeHundredLastMonth", "Any charges above $300 last month?",
     s(min=300, dates=LAST_MONTH), ("list", "largest", 10)),
    ("uberRidesUnderFifteen", "List my Uber rides under $15",
     s("Uber", max=15), ("list", "newest", 10)),
    ("starbucksAboveTenThisYear", "List my Starbucks transactions that above $10 from the beginning of this year",
     s("Starbucks", min=10, dates=SINCE_JANUARY), ("list", "newest", 10)),
    ("groceryBillsHundredToTwoHundred", "How many grocery bills between $100 and $200 did I have in the past 3 months?",
     s(categories=["groceries"], min=100, max=200, dates=PAST_3_MONTHS), ("count",)),
    ("boughtOverTwoFiftyPastSixMonths", "What did I buy for more than $250 in the past 6 months?",
     s(min=250, dates=PAST_6_MONTHS), ("list", "largest", 10)),
    ("purchasesUnderFiveThisYear", "How many purchases under $5 did I make this year?",
     s(max=5, dates=THIS_YEAR), ("count",)),
    ("everOverTwoThousand", "Have I ever spent more than $2,000 in one go?",
     s(min=2000), ("nothing",)),

    # --- Biggest and smallest ---------------------------------------------
    ("biggestPurchaseLastMonth", "What was my biggest purchase last month?",
     s(dates=LAST_MONTH), ("largest",)),
    ("mostEverInOneTransaction", "What's the most I've ever spent in one transaction?",
     s(), ("largest",)),
    ("biggestGroceryBillThisYear", "Biggest grocery bill this year?",
     s(categories=["groceries"], dates=THIS_YEAR), ("largest",)),
    ("mostExpensiveUberRide", "What was my most expensive Uber ride?",
     s("Uber"), ("largest",)),
    ("cheapestCostcoPurchase", "What's the cheapest thing I bought at Costco?",
     s("Costco"), ("smallest",)),
    ("largestRestaurantBillPastSixMonths", "Largest restaurant bill in the past 6 months?",
     s(categories=["restaurants"], dates=PAST_6_MONTHS), ("largest",)),
    ("smallestAmazonOrderThisYear", "Smallest Amazon order this year?",
     s("Amazon", dates=THIS_YEAR), ("smallest",)),
    ("priciestFlightThisYear", "Priciest flight I booked this year?",
     s(categories=["airlines"], dates=THIS_YEAR), ("largest",)),

    # --- Averages ---------------------------------------------------------
    ("averageUberRide", "What's my average Uber ride cost?",
     s("Uber"), ("average",)),
    ("averageGroceryTrip", "On average, how much do I spend per grocery trip?",
     s(categories=["groceries"]), ("average",)),
    ("averageTimHortonsPastSixMonths", "Average Tim Hortons order in the past 6 months?",
     s("Tim Hortons", dates=PAST_6_MONTHS), ("average",)),
    ("averageRestaurantBillLastMonth", "What was my average restaurant bill last month?",
     s(categories=["restaurants"], dates=LAST_MONTH), ("average",)),
    ("typicalStarbucksVisit", "How much does a typical Starbucks visit cost me?",
     s("Starbucks"), ("average",)),

    # --- When -------------------------------------------------------------
    ("lastCostcoTrip", "When did I last go to Costco?",
     s("Costco"), ("latest",)),
    ("lastUberRide", "When was my last Uber ride?",
     s("Uber"), ("latest",)),
    ("lastBestBuyPurchase", "What did I last buy at Best Buy?",
     s("Best Buy"), ("latestAmount",)),
    ("lastFillUp", "When did I last fill up on gas?",
     s(categories=["gasStations"]), ("latest",)),
    ("lastMovieNight", "When was the last time I went to the movies?",
     s(categories=["entertainment"]), ("latest",)),
    ("lastRogersCharge", "When did Rogers last charge me?",
     s("Rogers"), ("latestAmount",)),
    ("firstIkeaTrip", "When did I first shop at IKEA?",
     s("IKEA"), ("earliest",)),
    ("goodLifeThisMonth", "Did my GoodLife membership come out this month?",
     s("GoodLife Fitness", dates=THIS_MONTH), ("latestAmount",)),

    # --- Show me ----------------------------------------------------------
    ("lastThreeUberRides", "Show my last 3 Uber rides",
     s("Uber"), ("list", "newest", 3)),
    ("netflixChargesInAugust", "Show me my Netflix charges in August",
     s("Netflix", dates=("2026-08-01", "2026-08-31")), ("listDates",)),
    ("whatDidIBuyYesterday", "What did I buy yesterday?",
     s(dates=("2026-10-05", "2026-10-05")), ("list", "newest", 10)),
    ("lastWeekendSpending", "What did I spend money on last weekend?",
     s(dates=("2026-10-03", "2026-10-04")), ("list", "newest", 10)),
    ("everythingAtCactusClub", "List everything I bought at Cactus Club",
     s("Cactus Club Cafe"), ("list", "newest", 10)),
    ("threeBiggestPurchasesThisYear", "What were my 3 biggest purchases this year?",
     s(dates=THIS_YEAR), ("list", "largest", 3)),
    ("allLyftRides", "Show my Lyft rides",
     s("Lyft"), ("list", "newest", 10)),

    # --- Where and which ----------------------------------------------------
    ("topCity", "Which city did I spend the most in?",
     s(), ("group", "city", None)),
    ("topGroceryStore", "Where do I spend the most on groceries?",
     s(categories=["groceries"]), ("group", "merchant", None)),
    ("topCategoryLastMonth", "What category ate up most of my money last month?",
     s(dates=LAST_MONTH), ("group", "category", None)),
    ("topEatingOutMonth", "Which month did I spend the most on eating out?",
     s(categories=["restaurants"]), ("group", "month", None)),
    ("spentInQuebec", "How much did I spend in Quebec?",
     s(), ("group", "province", "Quebec")),
    ("spentInVancouver", "How much did I spend while I was in Vancouver?",
     s(), ("group", "city", "Vancouver")),
    ("spentInMontreal", "How much did I spend in Montreal?",
     s(), ("group", "city", "Montreal")),
    ("topStoreThisYear", "Which store did I spend the most at this year?",
     s(dates=THIS_YEAR), ("group", "merchant", None)),
    ("topRideshare", "Where did most of my rideshare money go?",
     s(categories=["taxiAndRideshare"]), ("group", "merchant", None)),
    ("topGasStation", "Which gas station do I use the most?",
     s(categories=["gasStations"]), ("group", "merchant", None)),
    ("augustByCategory", "Break down my August spending by category",
     s(dates=("2026-08-01", "2026-08-31")), ("group", "category", None)),
    ("mostExpensiveMonth", "What was my most expensive month?",
     s(), ("group", "month", None)),
    ("topUberCity", "In which city did I spend the most on Uber?",
     s("Uber"), ("group", "city", None)),
    ("spentInBanff", "How much did I spend in Banff?",
     s(), ("group", "city", "Banff")),

    # --- Nothing there ----------------------------------------------------
    ("walmartLastWeek", "How much did I spend at Walmart last week?",
     s("Walmart", dates=("2026-09-27", "2026-10-03")), ("nothing",)),
    ("appleStoreThisMonth", "Did I spend anything at the Apple Store this month?",
     s("Apple Store", dates=THIS_MONTH), ("nothing",)),
    ("lyftPastMonth", "Any Lyft rides in the past month?",
     s("Lyft", dates=("2026-09-06", TODAY)), ("nothing",)),
    ("sephoraLastMonth", "Did I buy anything at Sephora last month?",
     s("Sephora", dates=LAST_MONTH), ("nothing",)),
    ("spotifyThisYear", "Did Spotify charge me this year?",
     s("Spotify", dates=THIS_YEAR), ("nothing",)),
]

assert len(CASES) == 100, len(CASES)
assert len({c[0] for c in CASES}) == 100
assert len({c[1] for c in CASES}) == 100
