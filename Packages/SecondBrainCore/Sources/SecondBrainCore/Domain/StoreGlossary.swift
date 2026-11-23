import Foundation

/// One entry in the store-terms reference.
public struct GlossaryTerm: Identifiable, Hashable, Sendable {
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case roles, leadership, stocking, inventory, digital, frontEnd, fresh, metrics, safety, equipment
        case people, layout, departments, acronyms, slang

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .roles: return "Roles & titles"
            case .leadership: return "Leadership language"
            case .stocking: return "Stocking & backroom"
            case .inventory: return "Inventory & salesfloor"
            case .digital: return "OPD & digital"
            case .frontEnd: return "Front End"
            case .fresh: return "Fresh & food"
            case .metrics: return "Metrics & reports"
            case .safety: return "Safety & AP"
            case .equipment: return "Equipment"
            case .people: return "Scheduling & people"
            case .layout: return "Store layout"
            case .departments: return "Department numbers"
            case .acronyms: return "Other acronyms"
            case .slang: return "Everyday slang"
            }
        }

        public var systemImage: String {
            switch self {
            case .roles: return "person.badge.key"
            case .leadership: return "person.3"
            case .stocking: return "shippingbox"
            case .inventory: return "barcode"
            case .digital: return "bag"
            case .frontEnd: return "cart"
            case .fresh: return "leaf"
            case .metrics: return "chart.bar"
            case .safety: return "exclamationmark.shield"
            case .equipment: return "wrench.and.screwdriver"
            case .people: return "calendar.badge.clock"
            case .layout: return "map"
            case .departments: return "number"
            case .acronyms: return "textformat.abc"
            case .slang: return "bubble.left.and.bubble.right"
            }
        }
    }

    /// How settled a term is, so outdated or local language isn't mistaken for current policy.
    public enum Usage: String, Sendable {
        case current, legacy, informal, varies

        public var label: String? {
            switch self {
            case .current: return nil
            case .legacy: return "Older term"
            case .informal: return "Informal"
            case .varies: return "Varies by store"
            }
        }
    }

    public let term: String
    /// A second spelling given in parentheses, e.g. "Overstock (OS)" → "OS".
    public let alias: String?
    public let meaning: String
    public let category: Category
    public let usage: Usage

    public var id: String { category.rawValue + ":" + term }

    /// The term as written, with its alias: "Overstock (OS)".
    public var displayTerm: String { alias.map { "\(term) (\($0))" } ?? term }

    /// Department number for entries in `.departments`.
    public var departmentNumber: Int? {
        guard category == .departments else { return nil }
        return Int(term.replacingOccurrences(of: "Dept ", with: ""))
    }
}

/// A reference of common store terms, acronyms and slang, compiled from public employee
/// discussions and retail references. Not official: meanings change and vary by store and market.
public enum StoreGlossary {
    public static let disclaimer = "Compiled from public employee sources and retail references — not official. Terms change over time and vary by store and market, so confirm anything that matters with your leaders or the approved company resource."

    public static let terms: [GlossaryTerm] = {
        var result: [GlossaryTerm] = []
        for (category, block) in blocks {
            for raw in block.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count >= 2 else { continue }
                var term = parts[0]
                var alias: String?
                if term.hasSuffix(")"), let open = term.lastIndex(of: "(") {
                    alias = String(term[term.index(after: open)..<term.index(before: term.endIndex)])
                    term = term[..<open].trimmingCharacters(in: .whitespaces)
                }
                let usage: GlossaryTerm.Usage
                switch parts.count > 2 ? parts[2] : "" {
                case "l": usage = .legacy
                case "i": usage = .informal
                case "v": usage = .varies
                default: usage = category == .slang ? .informal : .current
                }
                result.append(GlossaryTerm(term: term, alias: alias, meaning: parts[1], category: category, usage: usage))
            }
        }
        return result
    }()

    // MARK: Lookup

    /// Every entry whose term or alias is exactly `word` (case-insensitive) — more than one when a term
    /// has several meanings, such as MOD or BOB.
    public static func lookup(_ word: String) -> [GlossaryTerm] {
        let key = normalize(word)
        guard !key.isEmpty else { return [] }
        return terms.filter { normalize($0.term) == key || $0.alias.map(normalize) == key }
    }

    /// Ranked search: exact term, then prefix, then anywhere in the term, then the meaning.
    public static func search(_ query: String, in category: GlossaryTerm.Category? = nil) -> [GlossaryTerm] {
        let pool = category.map { c in terms.filter { $0.category == c } } ?? terms
        let key = normalize(query)
        guard !key.isEmpty else { return pool }
        var ranked: [(GlossaryTerm, Int)] = []
        for entry in pool {
            let names = [normalize(entry.term)] + (entry.alias.map { [normalize($0)] } ?? [])
            let rank: Int
            if names.contains(key) { rank = 0 }
            else if names.contains(where: { $0.hasPrefix(key) }) { rank = 1 }
            else if names.contains(where: { $0.contains(key) }) { rank = 2 }
            else if normalize(entry.meaning).contains(key) { rank = 3 }
            else { continue }
            ranked.append((entry, rank))
        }
        return ranked.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.term.count < $1.0.term.count }.map(\.0)
    }

    /// Terms that have more than one meaning across the reference.
    public static var termsWithSeveralMeanings: [String] {
        var counts: [String: (String, Int)] = [:]
        for entry in terms {
            for name in [entry.term] + (entry.alias.map { [$0] } ?? []) {
                let key = normalize(name)
                counts[key] = (counts[key]?.0 ?? name, (counts[key]?.1 ?? 0) + 1)
            }
        }
        return counts.values.filter { $0.1 > 1 }.map(\.0).sorted()
    }

    /// Department name for a store department number, e.g. 94 → "Produce".
    public static func departmentName(number: Int) -> String? {
        terms.first { $0.departmentNumber == number }?.meaning
    }

    /// Acronyms written in capitals in `text` that the reference knows, in order of appearance,
    /// e.g. "Review FTPR and nil picks with the OPD TL" → FTPR, OPD, TL.
    public static func acronymsMentioned(in text: String, limit: Int = 6) -> [GlossaryTerm] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\w/&])[A-Z][A-Z0-9/&]{1,5}(?![\w/&])"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        var result: [GlossaryTerm] = []
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            guard !ignoredCapitals.contains(token), seen.insert(token).inserted else { continue }
            let hits = terms.filter { $0.term == token || $0.alias == token }
            guard let best = hits.first(where: { $0.category != .layout }) ?? hits.first else { continue }
            result.append(best)
            if result.count == limit { break }
        }
        return result
    }

    /// Capitalised words too common in ordinary writing to explain.
    static let ignoredCapitals: Set<String> = ["ON", "OH", "OO", "CO", "PO", "OT", "PI", "AT", "TA", "DC", "FC", "GM", "OS", "IT"]

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: Data
    // Format: Term (Alias)|Meaning|usage — usage is blank (current), l (older term), i (informal) or v (varies).

    static let blocks: [(GlossaryTerm.Category, String)] = [
        (.roles, """
        SM|Store Manager — leads the whole store
        SL|Store Lead|v
        Coach|Salaried manager over an area of the store (as a verb, a performance conversation)
        Coach Trainee|Associate training for a Coach role
        TL|Team Lead — leads a team of associates under a Coach
        TA|Team Associate
        AT|Academy Trainer
        PL|People Lead — the store's HR leader
        AP|Asset Protection
        APA|Asset Protection Associate
        APCH|Asset Protection Customer Host
        AP Coach|Asset Protection Coach
        FE TL|Front End Team Lead
        ACCM|Auto Care Center Manager
        ACC TL|Auto Care Center Team Lead
        O/N TL|Overnight Team Lead
        Stocking TL|Stocking Team Lead
        OPD TL|Online Pickup and Delivery Team Lead
        CSS|Customer Service Supervisor
        MOD|Manager on Duty (also short for modular)
        MIT|Manager in Training
        Market Manager|Leader over several stores
        Market Coach|Market-level operations leader
        Regional Manager|Leader over a group of markets
        Home Office (HO)|Corporate headquarters
        Field|Store and market operations outside the Home Office
        ASM|Assistant Store Manager|l
        COM|Co-Manager|l
        DM|Department Manager|l
        CSM|Customer Service Manager|l
        APASM|Asset Protection Assistant Store Manager|l
        DAPM|District Asset Protection Manager|l
        """),
        (.leadership, """
        Span of Control|Number of direct reports a leader manages
        Accountability|Holding people to agreed expectations
        Ownership|Taking responsibility for an area or result
        Delegation|Assigning tasks and responsibilities to someone else
        Follow-up|Verifying that assigned work was completed
        Succession Planning|Preparing associates for future leadership roles
        Talent Pipeline|Associates being developed for advancement
        Bench|People ready, or being readied, for promotion
        Development Plan|Structured plan to build skills and performance
        Calibration|Comparing performance and talent assessments across leaders
        One-on-One|Individual conversation between a leader and an associate
        Huddle|Short team meeting to share priorities
        Touch Base|Brief follow-up conversation
        Walk|Leadership inspection of store conditions and execution
        Store Tour|Management walkthrough of store operations
        Market Walk|Walkthrough by market leadership
        Business Review|Review of store or department performance
        Action Plan|Specific steps to close a performance gap
        Ownership Walk|Walkthrough focused on accountability and execution
        """),
        (.stocking, """
        Stock 1|Morning stocking team
        Stock 2|Evening stocking team
        Stock 3|Overnight stocking team
        CAP|Customer Availability Process — older name for the stocking teams|l
        CAP 1|Former name for the morning stocking team (now Stock 1)|l
        CAP 2|Former name for the afternoon/evening stocking team (now Stock 2)|l
        CAP 3|Former name for the overnight stocking team (now Stock 3)|l
        ON (O/N)|Overnights
        ON Process|Overnight stocking process
        Freight|Merchandise received for stocking
        GM Freight|General merchandise freight
        Grocery Freight|Grocery merchandise freight
        Remix|Mixed grocery freight that needs breaking down
        Remix Breakdown|Separating mixed grocery freight
        HVDC|High Volume Distribution Center
        RDC|Regional Distribution Center
        FDD|Frozen, Dairy and Deli
        DSD|Direct Store Delivery — the vendor delivers straight to the store (also Dept 95)
        Live Freight|Freight being unloaded or worked right now
        Unworked Freight|Freight that hasn't been stocked yet
        Overstock (OS)|Product that won't fit in its shelf location
        Topstock|Shelf space above the selling shelf; also moving product up there
        Topstocking|Moving merchandise to topstock
        VizPick|Process for picking merchandise from backroom bins and topstock
        Cap Bins|Older process for finding merchandise in backroom bins|l
        Bin|Assigned backroom inventory location
        Pick|Pulling merchandise from backroom inventory
        Pick Rate|Rate at which assigned picks are completed
        Pick Walk|Group of backroom picks assigned to one associate
        Scan|Scanning merchandise or locations with a handheld
        Backstock|Merchandise sent back to the backroom
        Downstack|Breaking pallets into smaller groups
        Breakpack|Case holding several smaller individual units
        Casepack|Merchandise packed as a full case
        Mixed Pallet|Pallet with several products or departments
        Pulling Freight|Bringing freight out to the salesfloor
        Working Freight|Stocking merchandise onto the shelves
        Freight Flow|Movement of freight from receiving to the salesfloor
        Freight Completion|Finishing the assigned freight workload
        Truck Process|Unloading and processing a delivery, end to end
        Unload|Taking merchandise off a trailer
        Line|Conveyor used while unloading a truck
        Throwing Freight|Moving cases off the conveyor; informally, stocking cases|i
        Palletize|Building freight onto pallets
        Condense|Combining partly filled pallets or bins
        Rework|Correcting merchandise that was organized wrong
        Replenishment|Restocking based on what has sold
        Bin Audit|Checking bin contents against system inventory
        Overstock Verification|Checking whether overstock can now go to the shelf
        Clean Backroom|Backroom free of misplaced freight, trash and safety hazards
        """),
        (.inventory, """
        OH|On Hand inventory
        OO|On Order
        ISA|Inventory systems adjustment|v
        ISA Investigation|Researching an inventory discrepancy|v
        PI|Physical Inventory
        UPC|Universal Product Code
        SKU|Stock Keeping Unit
        Item Number|Company-assigned merchandise number
        Modular (Mod)|Approved shelf layout for merchandise
        Mod Flex|Flexible modular arrangement
        Mod Set|Setting merchandise to the modular
        Mod Reset|Rebuilding or updating an existing modular
        Modular Integrity|How accurately the shelf matches the modular
        Planogram (POG)|Diagram showing where merchandise belongs
        Facing|Number of product fronts visible on a shelf
        Facing Up|Pulling merchandise forward so it presents well
        Zoning|Organizing shelves and making merchandise presentable
        Fast Zone|Quick shelf recovery
        Plugging|Putting merchandise wherever it fits instead of its home location
        Flexing|Temporarily placing merchandise in another location
        Feature-to-Home|Returning promotional merchandise to its home location
        Home|An item's primary selling location
        Secondary Location|Additional place an item is displayed
        Feature|Promotional display, or its assigned location
        Endcap|Display at the end of an aisle
        Wing Stack|Freestanding promotional stack
        Sidekick|Secondary display attached to a shelf or fixture
        PDQ|Pre-packed merchandise display
        Stack Base|Base used to build a merchandise stack
        Action Alley|Main salesfloor walkways and their feature displays
        Price Change|Updating an item's retail price
        Clearance|Merchandise being reduced to sell through
        Markdown|Reduction in selling price
        Rollback|Temporary price reduction
        Reset|Updating a section or merchandising layout
        Set|Installing a modular or display
        Seasonal Transition|Changing merchandise for the next season
        Feature Quantity|Merchandise allocated to a promotional display
        Phantom Inventory|System shows inventory that can't be found
        Shrink|Inventory loss
        Inventory Accuracy|How closely system counts match what's physically there
        Cycle Count|Targeted inventory count
        On-Hand Adjustment|Correcting the recorded inventory quantity
        Zero On-Hand|System shows zero inventory
        Negative On-Hand|System shows a negative quantity
        In-Stock|Product is available for customers
        Out of Stock (OOS)|Product is unavailable
        Shelf Availability|Whether merchandise is on the salesfloor
        Shelf Capacity|Most merchandise that fits in a shelf location
        """),
        (.digital, """
        OPD|Online Pickup and Delivery
        OGP|Online Grocery Pickup|l
        SFS|Ship From Store
        PUT|Pick Up Today|l
        BOPIS|Buy Online, Pick Up In Store
        BODFS|Buy Online, Deliver From Store
        GIF 2|Grocery Intelligent Fulfillment — the app used to pick orders
        Pick Walk|Group of customer orders assigned to one picker
        FTPR|First Time Pick Rate — share of items picked correctly on the first attempt
        FTP|First Time Pick|i
        Nil Pick|Item can't be found while picking (not the same as a substitution)
        Sub|Substitution
        Substitution Rate|How often unavailable items are replaced
        Pre-Sub|Substitute chosen before the original item is picked
        Post-Sub|Substitute chosen after the original item can't be found
        Exception|Order item that needs extra attention
        Exception Management|Handling unavailable or problem items
        Staging|Organizing finished orders for pickup or delivery
        Pre-Stage|Preparing orders ahead of the pickup or delivery time
        Dispense|Handing the order to the customer or driver
        Wait Time|How long a customer waits for their order
        On-Time Pick|Orders picked within their required window
        On-Time Delivery|Delivery completed in the expected window
        Order Quality|Accuracy and condition of orders
        Oversized|Merchandise that needs special handling
        Oversize Walk|Pick walk for oversized merchandise
        Ambient|Room-temperature items
        Chilled|Refrigerated items
        """),
        (.frontEnd, """
        FE|Front End
        SCO|Self Checkout
        SCO Host|Associate who monitors self-checkout
        Service Desk|Customer service and returns counter
        CO|Cash Office
        Cash Recycler|Machine that processes and dispenses cash
        CFT|Cash Fund Transfer
        BOB|Bottom of Basket — checking under the cart (in Bakery it can mean Bakery Operations Book)
        LISA|Look Inside Always
        EAS|Electronic Article Surveillance
        Receipt Check|Verifying a customer's purchases at the door
        Cart Associate|Associate who collects carts (informally, cart pusher)
        Code Adam|Missing child procedure
        Code White|Often used for an accident or injury — local procedures vary|v
        Code Blue|Often used for a medical emergency — local procedures vary|v
        Price Override|Authorized price adjustment at the register
        Price Match|Matching an eligible competitor's price
        10-Foot Rule|Greet and help customers who come within ten feet
        5-Star|Customer satisfaction rating program|v
        NPS|Net Promoter Score
        CFF|Clean, Fast, Friendly|l
        """),
        (.fresh, """
        Fresh|Produce, Meat, Bakery and Deli
        FCAP|Fresh Customer Availability Process|l
        Meat Wall|Refrigerated meat display
        Wet Wall|Refrigerated produce wall
        97 Wall|Refrigerated packaged meat and deli wall (Dept 97)
        CVP|Markdown and freshness process for fresh product|v
        Culling|Removing damaged, spoiled or unsellable product
        Rotation|Moving older product to the front
        FIFO|First In, First Out
        FEFO|First Expired, First Out
        Date Code|Expiration or freshness date on a product
        Expiration Pull|Removing expired merchandise
        Out of Date|Product past its allowed sell date
        Fresh Claims|Claims for fresh department merchandise
        Food Safety|Procedures that prevent contamination and unsafe handling
        Temp Log|Recorded temperature checks
        Cold Chain|Keeping required temperatures throughout handling
        Waste|Product thrown out for damage, expiration or spoilage
        Donation|Eligible food given to charity
        Production|Preparing fresh or ready-to-sell product
        Throwaway|Discarding unsellable product
        """),
        (.metrics, """
        Sales|Total merchandise revenue
        Comp Sales|Comparable sales growth
        Comp|Comparison against a comparable earlier period
        Walmart Week|Runs Saturday through Friday; fiscal weeks count from the week containing February 1
        LY|Last Year
        LW|Last Week
        WTD|Week to Date (the business week runs Saturday–Friday)
        MTD|Month to Date
        QTD|Quarter to Date
        YTD|Year to Date
        YOY|Year Over Year
        WOW|Week Over Week
        In-Stock %|Percentage of items available
        Nil Pick Rate|Percentage of picks where the item couldn't be found
        VizPick %|Measure of VizPick execution|v
        Topstock %|Measure of topstock execution|v
        Shrink %|Inventory loss as a percentage of sales
        OSA|On-Shelf Availability
        OSCA|On-Shelf Customer Availability
        S2D|Store-to-Door
        SPLH|Sales Per Labor Hour
        UPH|Units Per Hour
        PPH|Picks Per Hour
        WOSH|Worked Over Scheduled Hours — time beyond the schedule (not the same as overtime)
        WSH|Worked Scheduled Hours|v
        WOB|Wage Over Budget|v
        OT|Overtime
        Labor|Paid workforce hours
        Wages|Labor expense
        Productivity|Output relative to time or labor
        Budgeted Hours|Approved labor allocation
        Actual Hours|Hours actually worked
        Variance|Difference between expected and actual results
        Turnover|Rate of associates leaving
        Retention|Keeping associates
        Absenteeism|Missed scheduled work
        Headcount|Total number of associates
        Coverage|Staffing available for an area or shift
        Schedule Adherence|Working the published schedule
        DPSPW|Dollars Per Store Per Week
        UPSPW|Units Per Store Per Week
        """),
        (.safety, """
        Safety Walk|Inspection for safety hazards
        Safety Sweep|Checking assigned areas for hazards
        Safety Observation|Documented observation of workplace safety
        PPE|Personal Protective Equipment
        LOTO|Lockout/Tagout
        OSHA|Occupational Safety and Health Administration
        SDS|Safety Data Sheet (formerly MSDS)
        Incident|Workplace event involving injury, damage or risk
        Near Miss|Event that could have caused an injury
        Hazard|Unsafe condition or behavior
        Ergonomics|Safe body mechanics and workplace design
        Spill Response|Procedures for containing and cleaning spills
        Fire Drill|Fire evacuation practice (informally, a sudden urgent assignment)
        Evacuation|Safely clearing the building
        Emergency Action Plan|Procedures for responding to emergencies
        Active Threat|Emergency with an immediate threat to people
        Safety Champion|Associate who supports safety efforts
        Safety Committee|Group focused on workplace safety
        Claims|Processing damaged merchandise (can also mean injury claims)
        Case Integrity|Proper documentation and handling of claims
        Internal Theft|Theft involving associates
        External Theft|Theft by customers or outside people
        ORC|Organized Retail Crime
        CCTV|Closed-Circuit Television
        """),
        (.equipment, """
        PLE|Powered Lifting Equipment
        PIT|Powered Industrial Truck
        EPJ|Electric Pallet Jack
        Walkie Stacker|Powered equipment for moving and lifting pallets
        Walkie Rider|Ride-on powered pallet jack
        Forklift|Powered truck for lifting and moving freight
        Scissor Lift|Elevated work platform
        Manual Jack|Non-powered pallet jack
        Pre-Use Inspection|Required equipment check before operating
        Baler|Machine that compresses cardboard into bales
        Bale|Compressed block of cardboard or recyclables
        Compactor|Machine that compacts trash
        """),
        (.people, """
        Workday|HR and workforce management platform
        Me@Walmart|Associate mobile app
        OneWalmart|Associate portal
        The Wire|Older name for the associate portal|l
        WIN|Associate identification number — don't store it in Second Brain
        BYOD|Bring Your Own Device
        GTA|Global Time and Attendance
        PTO|Paid Time Off
        PPTO|Protected Paid Time Off
        LOA|Leave of Absence
        FMLA|Family and Medical Leave Act
        ADA|Americans with Disabilities Act
        Callout|An associate reporting an absence
        NCNS|No Call, No Show
        Open Availability|Available without major scheduling limits
        Availability Change|Updating an associate's available hours
        Schedule Exception|A problem or deviation with someone's schedule
        Meal Exception|Missed meal-break timing requirement
        Meal Punch|Recording the start or end of a meal break
        Time Adjustment|Correction to recorded work time
        Coaching|Documented performance or conduct conversation
        DA|Disciplinary Action (can also mean Display Allowance)
        Open Door|Process for raising concerns with higher management
        Ethics|Channel for reporting ethics concerns
        People Lead|Store HR leader
        Orientation|New associate onboarding
        ULearn|Learning and training platform
        CBL|Computer-Based Learning|l
        Academy|Company training program
        Cross-Training|Training associates in more areas
        Job Code|Position classification
        Transfer|Moving to another department or store
        Development Opportunity|Assignment that builds skills
        Sponsor|Leader who advocates for an associate's growth
        Champion|Person responsible for an initiative
        """),
        (.layout, """
        GM|General Merchandise
        Grocery|Food and grocery merchandise
        Consumables|Frequently used household and personal products
        Hardlines|Hardware, automotive, toys, sporting goods and similar
        Homelines|Household merchandise
        Softlines|Apparel and related merchandise
        HBA|Health and Beauty Aids
        OTC|Over-the-Counter pharmacy merchandise
        L&G|Lawn and Garden
        ACC|Auto Care Center
        TLE|Tire and Lube Express|l
        Race Track|Main circulation path around the salesfloor
        Back Action Alley|Rear salesfloor walkway
        Bowling Alley|Front-end walkway|i
        Bullpen|Self-checkout area|i
        Cart Rail|Shelving near the cart area
        Backroom|Associate-only operations area
        Receiving|Where deliveries are received
        Dock|Truck receiving and unloading area
        Trailer Yard|Where delivery trailers are staged
        Garden Center|Outdoor and seasonal merchandise area
        Cash Office|Cash management and accounting area
        Breakroom|Associate break area
        """),
        (.departments, """
        Dept 1|Candy and Tobacco
        Dept 2|Health and Beauty Aids
        Dept 3|Stationery
        Dept 4|Household Paper
        Dept 5|Media and Gaming
        Dept 6|Cameras and Photo
        Dept 7|Toys
        Dept 8|Pets
        Dept 9|Sporting Goods
        Dept 10|Automotive
        Dept 11|Hardware
        Dept 12|Paint
        Dept 13|Household Chemicals
        Dept 14|Cook and Dine
        Dept 16|Outdoor Living
        Dept 17|Home Décor
        Dept 18|Seasonal
        Dept 19|Crafts
        Dept 20|Bath
        Dept 21|Books
        Dept 22|Bedding
        Dept 23|Men's Apparel
        Dept 24|Boys' Apparel
        Dept 25|Shoes
        Dept 26|Infant Apparel
        Dept 27|Socks
        Dept 28|Hosiery
        Dept 29|Sleepwear
        Dept 30|Bras and Shapewear
        Dept 31|Ladies' Accessories
        Dept 32|Jewelry
        Dept 33|Girls' Apparel
        Dept 34|Misses and Juniors
        Dept 35|Plus Size and Maternity
        Dept 36|Outerwear and Swimwear
        Dept 37|Auto Care Center
        Dept 38|Pharmacy Prescriptions
        Dept 40|OTC Pharmacy
        Dept 41|College and Pro Apparel
        Dept 44|Fabric
        Dept 46|Cosmetics
        Dept 48|Firearms
        Dept 49|Optical
        Dept 56|Lawn and Garden
        Dept 58|Wireless Services
        Dept 65|Fuel
        Dept 67|Celebrations
        Dept 69|Online Sales
        Dept 71|Furniture
        Dept 72|Electronics
        Dept 74|Storage and Organization
        Dept 77|Large Appliances
        Dept 79|Infant Consumables
        Dept 80|Service Deli
        Dept 81|Commercial Bread
        Dept 82|Impulse/Checkout
        Dept 85|Photo
        Dept 86|Financial Services
        Dept 87|Wireless Devices
        Dept 89|Travel
        Dept 90|Dairy
        Dept 91|Frozen
        Dept 92|Grocery
        Dept 93|Meat and Seafood
        Dept 94|Produce
        Dept 95|DSD Grocery
        Dept 96|Liquor
        Dept 97|Meat and Deli Wall
        Dept 98|Bakery
        Dept 99|Store Assets
        """),
        (.acronyms, """
        OBW|One Best Way
        EDLP|Every Day Low Price
        EDLC|Every Day Low Cost
        AES|Associate Engagement Survey
        ACNT|Associates in Critical Need Trust
        AMP|Activity Management Planner
        ASN|Advanced Shipping Notice
        DC|Distribution Center
        FC|Fulfillment Center
        GRS|Global Replenishment System
        JBP|Joint Business Planning
        LTP|Long-Term Plan
        POS|Point of Sale
        POP|Point of Purchase
        PLU|Price Look-Up
        PIP|Product in Pipeline
        STH|Ship to Home
        S2S|Site to Store
        WERCS|System for hazardous-materials and regulatory compliance data
        WOS|Weeks of Supply
        UOM|Unit of Measure
        VMI|Vendor Managed Inventory
        PO|Purchase Order
        EDI|Electronic Data Interchange
        AML|Anti-Money Laundering
        GWP|Great Workplace|l
        """),
        (.slang, """
        Blue Vest|Associates in general
        Walmart Math|A joke about unusual processes or expectations
        Getting Buried|Overwhelmed with workload
        Getting Killed|An exceptionally busy shift
        Getting Pulled|Reassigned to another department
        Covering|Temporarily running another area
        Zoning Up|Improving shelf presentation
        Zone Recovery|Restoring salesfloor presentation
        Running Freight|Stocking assigned merchandise
        Working Topstock|Working merchandise down from the top shelves
        Chasing Picks|Trying to finish outstanding VizPick work
        Chasing Metrics|Trying to improve performance numbers
        Walking the Store|Checking store conditions
        Walking Freight|Checking freight and stocking progress
        Walking the Business|Evaluating performance firsthand
        Clean as You Go|Keeping work areas organized while working
        Eating Hours|Using more labor hours than planned
        Cutting Hours|Reducing scheduled or worked labor
        Getting Sent Home|Released from work early
        Staying Over|Working past the scheduled end time
        Being Coached|Receiving documented corrective feedback
        Open Dooring|Escalating a concern to higher management
        Market Is Coming|Market leadership is visiting
        Regional Is Coming|Regional leadership is visiting
        Customer Ready|Store ready for customers
        Tour Ready|Store ready for a leadership walkthrough
        Store Ready|Store meeting expected standards
        Red Flag|Issue that needs management attention
        Green|Meeting a target
        Red|Missing a target
        Golden Zone|Area or metric performing especially well
        Put Out Fires|Handling immediate problems
        Moving the Needle|Making measurable improvement
        Low-Hanging Fruit|Easy improvements
        Owning the Area|Being responsible for an area and its results
        Setting the Tone|Establishing expectations and standards
        All Hands|Pulling associates from several areas onto one priority
        Jump In|Helping another team
        Clean Sweep|Thorough cleanup of an area
        Side Work|Tasks outside someone's main responsibilities
        Padlocked|Area or merchandise secured
        """)
    ]
}
