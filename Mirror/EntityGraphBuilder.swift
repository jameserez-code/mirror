import Foundation

// MARK: - Canonical Entity Models

struct EntityGraph: Codable {
    let id: String
    var confidence: EntityGraphConfidence
    var entities: [EntityNode]
    var relationships: [EntityRelationship]
    var fieldMappings: [FieldMapping]
    var lineagePaths: [DataLineagePath]

    struct EntityGraphConfidence: Codable {
        var entityConfidence: Double
        var relationshipConfidence: Double
        var mappingConfidence: Double
        var lineageConfidence: Double
        var overallConfidence: Double
    }
}

// MARK: - Entity Node

struct EntityNode: Codable, Identifiable {
    let id: String
    let entityType: EntityType
    let category: EntityCategory
    var name: String
    var source: EntitySource           // where this entity came from
    var confidence: Double
    var fields: [EntityField]           // structured field data
    var provenanceEvents: [String]      // event indices that produced this entity

    struct EntityField: Codable {
        var name: String                // e.g. "amount_due", "vendor_name"
        let value: String               // e.g. "$1,234.56", "Acme Corp"
        let dataType: FieldDataType    // inferred type
        let confidence: Double
        let extractedFrom: String       // "clipboard", "typed_text", "ocr", "header"
        let alternatives: [String]?     // other possible values (for disambiguation)
    }

    enum FieldDataType: String, Codable {
        case currencyAmount
        case date
        case emailAddress
        case phoneNumber
        case personName
        case companyName
        case address
        case identifier       // invoice #, order #, etc.
        case url
        case freeText
        case number
        case boolean
    }

    struct EntitySource: Codable {
        let application: String         // "gmail", "sheets", "chrome", "clipboard"
        let url: String?                // source URL if web-based
        let artifactId: String?         // links to ExtractedArtifact
        let extractionMethod: String    // "clipboard_snapshot", "typed_text", "ocr", "field_detection"
    }

    enum EntityCategory: String, Codable {
        case businessObject    // Invoice, Customer, Lead, etc.
        case document          // Email, PDF, Spreadsheet, etc.
        case extractedValue    // a single value (CurrencyAmount, Date, etc.)
    }
}

// MARK: - Entity Type Registry

struct EntityType: Codable, RawRepresentable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    // Business Objects
    static let invoice = EntityType(rawValue: "Invoice")
    static let customer = EntityType(rawValue: "Customer")
    static let lead = EntityType(rawValue: "Lead")
    static let contact = EntityType(rawValue: "Contact")
    static let order = EntityType(rawValue: "Order")
    static let payment = EntityType(rawValue: "Payment")
    static let expense = EntityType(rawValue: "Expense")
    static let product = EntityType(rawValue: "Product")
    static let vendor = EntityType(rawValue: "Vendor")
    static let employee = EntityType(rawValue: "Employee")

    // Documents
    static let email = EntityType(rawValue: "Email")
    static let pdf = EntityType(rawValue: "PDF")
    static let spreadsheet = EntityType(rawValue: "Spreadsheet")
    static let form = EntityType(rawValue: "Form")
    static let website = EntityType(rawValue: "Website")
    static let file = EntityType(rawValue: "File")
    static let image = EntityType(rawValue: "Image")

    // Extracted Values
    static let currencyAmount = EntityType(rawValue: "CurrencyAmount")
    static let date = EntityType(rawValue: "Date")
    static let emailAddress = EntityType(rawValue: "EmailAddress")
    static let phoneNumber = EntityType(rawValue: "PhoneNumber")
    static let personName = EntityType(rawValue: "PersonName")
    static let companyName = EntityType(rawValue: "CompanyName")
    static let address = EntityType(rawValue: "Address")
    static let identifier = EntityType(rawValue: "Identifier")
    static let url = EntityType(rawValue: "URL")
    static let textBlock = EntityType(rawValue: "TextBlock")

    var category: EntityNode.EntityCategory {
        switch self {
        case .invoice, .customer, .lead, .contact, .order, .payment, .expense, .product, .vendor, .employee:
            return .businessObject
        case .email, .pdf, .spreadsheet, .form, .website, .file, .image:
            return .document
        default:
            return .extractedValue
        }
    }
}

// MARK: - Entity Relationship

struct EntityRelationship: Codable, Identifiable {
    let id: String
    let sourceEntityId: String
    let targetEntityId: String
    let relationshipType: RelationshipType
    var confidence: Double
    var metadata: RelationshipMetadata

    enum RelationshipType: String, Codable {
        case contains       // parent contains child (Email contains PDF)
        case references     // entity references another (Invoice references Customer)
        case derives        // entity was extracted from another (Amount from Invoice)
        case mapsTo         // field maps to another field (source_amount → target_column)
        case belongsTo      // child belongs to parent (LineItem belongs to Invoice)
        case sameAs         // two entities represent the same thing (dedup)
    }

    struct RelationshipMetadata: Codable {
        var transformation: String?    // "extract", "copy", "format", "calculate"
        var evidence: [String]?        // how we know this relationship exists
    }
}

// MARK: - Field Mapping

struct FieldMapping: Codable, Identifiable {
    let id: String
    let sourceEntityId: String
    let sourceFieldName: String
    let targetEntityId: String
    let targetFieldName: String
    var mappingType: MappingType
    var confidence: Double
    var metadata: MappingMetadata

    enum MappingType: String, Codable {
        case directCopy              // value copied verbatim
        case copyAndFormat           // value copied with formatting change
        case compute                  // value derived via transformation
        case lookUp                   // value looked up from reference data
        case inferred                  // mapping inferred from column headers
    }

    struct MappingMetadata: Codable {
        var sourceValue: String?     // the actual value that was copied
        var targetValue: String?     // the value that was pasted
        var clipboardMatch: Bool?    // was the clipboard value matched?
        var headerMatch: Bool?       // do field names match column headers?
        var valueSimilarity: Double? // 0.0-1.0 string similarity
        var temporalProximity: Double? // seconds between copy and paste
    }
}

// MARK: - Data Lineage Path

struct DataLineagePath: Codable, Identifiable {
    let id: String
    let description: String
    let nodes: [LineageNode]         // ordered chain of entities
    var confidence: Double

    struct LineageNode: Codable {
        let entityId: String
        let entityName: String
        let entityType: String
        let transformation: String?  // what happened at this step
    }
}

// MARK: - Entity Graph Builder

struct EntityGraphBuilder {

    // MARK: - Main Entry Point

    static func build(
        events: [EventTapManager.CapturedEvent],
        actions: [SemanticAction] = [],
        artifacts: [ExtractedArtifact] = [],
        graph: WorkflowGraph? = nil
    ) -> EntityGraph {
        let graphId = UUID().uuidString
        let entities = extractEntities(from: events, actions: actions, artifacts: artifacts)
        let relationships = extractRelationships(from: entities, actions: actions, artifacts: artifacts)
        let mappings = detectFieldMappings(from: events, entities: entities, actions: actions)
        let lineage = buildLineagePaths(from: entities, relationships: relationships, mappings: mappings)
        let confidence = computeConfidence(entities: entities, relationships: relationships, mappings: mappings, lineage: lineage)

        return EntityGraph(
            id: graphId,
            confidence: confidence,
            entities: entities,
            relationships: relationships,
            fieldMappings: mappings,
            lineagePaths: lineage
        )
    }

    // MARK: - Step 1: Entity Extraction

    private static func extractEntities(
        from events: [EventTapManager.CapturedEvent],
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> [EntityNode] {
        var entities: [EntityNode] = []
        var entityId = 0

        // Extract from artifacts
        for artifact in artifacts {
            let entityType = mapArtifactToEntityType(artifact)
            entityId += 1
            var entity = EntityNode(
                id: "entity\(entityId)",
                entityType: entityType,
                category: entityType.category,
                name: artifact.title,
                source: EntityNode.EntitySource(
                    application: artifact.sourceApp,
                    url: artifact.url,
                    artifactId: artifact.id,
                    extractionMethod: "field_detection"
                ),
                confidence: artifact.confidence,
                fields: artifact.fields.map { field in
                    EntityNode.EntityField(
                        name: field.name,
                        value: field.value,
                        dataType: classifyDataType(field.value, fieldName: field.name),
                        confidence: artifact.confidence,
                        extractedFrom: field.detectedFrom,
                        alternatives: nil
                    )
                },
                provenanceEvents: []
            )

            // Enrich field names from domain context
            entity = enrichFieldNames(entity, domain: artifact.domain)
            entities.append(entity)
        }

        // Extract standalone values from clipboard
        entityId = extractClipboardEntities(events: events, entities: &entities, startId: entityId)

        // Extract typed text entities
        entityId = extractTypedTextEntities(events: events, actions: actions, entities: &entities, startId: entityId)

        return entities
    }

    private static func mapArtifactToEntityType(_ artifact: ExtractedArtifact) -> EntityType {
        switch artifact.artifactType {
        case "invoice_tracker", "invoice_email":
            return .invoice
        case "lead_list":
            return .lead
        case "contact_list":
            return .contact
        case "expense_tracker", "receipt_email":
            return .expense
        case "financial_data", "financial_tracker":
            return .payment
        case "report":
            return .spreadsheet
        case "linkedin_profile":
            return .lead
        case "email":
            return .email
        case "spreadsheet", "google_sheet":
            return .spreadsheet
        case "web_page":
            return .website
        default:
            return .file
        }
    }

    private static func classifyDataType(_ value: String, fieldName: String) -> EntityNode.FieldDataType {
        let lower = fieldName.lowercased()
        let val = value.trimmingCharacters(in: .whitespaces)

        // By field name
        if lower.contains("amount") || lower.contains("price") || lower.contains("total") || lower.contains("due") {
            return .currencyAmount
        }
        if lower.contains("date") || lower.contains("time") || lower.contains("created") || lower.contains("updated") {
            return .date
        }
        if lower.contains("email") || (val.contains("@") && val.contains(".")) {
            return .emailAddress
        }
        if lower.contains("phone") || lower.contains("tel") || lower.contains("mobile") {
            return .phoneNumber
        }
        if lower.contains("vendor") || lower.contains("company") || lower.contains("organization") {
            return .companyName
        }
        if lower.contains("name") || lower.contains("contact") || lower.contains("person") {
            return .personName
        }
        if lower.contains("address") || lower.contains("location") || lower.contains("street") {
            return .address
        }
        if lower.contains("url") || lower.contains("link") || val.hasPrefix("http") {
            return .url
        }
        if lower.contains("id") || lower.contains("number") || lower.contains("#") {
            return .identifier
        }

        // By value pattern
        if let r = val.range(of: #"\$\d+[.,]\d{2}"#, options: .regularExpression), r.lowerBound == val.startIndex {
            return .currencyAmount
        }
        if val.range(of: #"\d{1,2}/\d{1,2}/\d{2,4}"#, options: .regularExpression) != nil ||
           val.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            return .date
        }
        if val.contains("@") && val.contains(".") {
            return .emailAddress
        }
        if let n = Double(val.replacingOccurrences(of: ",", with: "")), n.isFinite {
            return .number
        }

        return .freeText
    }

    private static func enrichFieldNames(_ entity: EntityNode, domain: String) -> EntityNode {
        var enriched = entity

        // Domain-specific field name enrichment
        let fieldNameMap: [String: [String: String]] = [
            "accounts_payable": [
                "amount": "amount_due",
                "name": "vendor_name",
                "description": "invoice_description",
                "email": "vendor_email",
            ],
            "lead_generation": [
                "name": "lead_name",
                "email": "lead_email",
                "description": "lead_title",
                "url": "linkedin_url",
            ],
            "expense_management": [
                "amount": "expense_amount",
                "name": "merchant_name",
                "description": "expense_category",
                "date": "expense_date",
            ],
            "crm": [
                "name": "contact_name",
                "email": "contact_email",
            ],
        ]

        if let domainFields = fieldNameMap[domain] {
            enriched.fields = enriched.fields.map { field in
                var f = field
                if let mapped = domainFields[field.name] {
                    f.name = mapped
                }
                return f
            }
        }

        return enriched
    }

    // MARK: - Clipboard Entity Extraction

    private static func extractClipboardEntities(
        events: [EventTapManager.CapturedEvent],
        entities: inout [EntityNode],
        startId: Int
    ) -> Int {
        var entityId = startId

        // Find clipboard change events
        for (index, event) in events.enumerated() where event.type == "clipboardChange" {
            guard let content = event.clipboardSnapshot, content.count > 3 else { continue }

            // Try to parse structured data from clipboard
            let parsedValues = parseClipboardValue(content)

            if parsedValues.count == 1, let (label, value) = parsedValues.first {
                // Single value: create extracted value entity
                let dataType = classifyDataType(value, fieldName: label)
                entityId += 1
                entities.append(EntityNode(
                    id: "entity\(entityId)",
                    entityType: dataTypeToEntityType(dataType),
                    category: .extractedValue,
                    name: label,
                    source: EntityNode.EntitySource(
                        application: event.targetApp ?? "clipboard",
                        url: event.targetURL,
                        artifactId: nil,
                        extractionMethod: "clipboard_snapshot"
                    ),
                    confidence: 0.85,
                    fields: [
                        EntityNode.EntityField(
                            name: label,
                            value: value,
                            dataType: dataType,
                            confidence: 0.85,
                            extractedFrom: "clipboard",
                            alternatives: nil
                        )
                    ],
                    provenanceEvents: ["event\(index)"]
                ))
            } else if parsedValues.count >= 2 {
                // Multi-value: create or enrich a business object entity
                entityId += 1
                let domain = inferDomain(from: parsedValues)
                let entityType = entityTypeForDomain(domain)
                entities.append(EntityNode(
                    id: "entity\(entityId)",
                    entityType: entityType,
                    category: .businessObject,
                    name: entityType.rawValue,
                    source: EntityNode.EntitySource(
                        application: event.targetApp ?? "clipboard",
                        url: event.targetURL,
                        artifactId: nil,
                        extractionMethod: "clipboard_snapshot"
                    ),
                    confidence: 0.78,
                    fields: parsedValues.map { label, value in
                        EntityNode.EntityField(
                            name: label,
                            value: value,
                            dataType: classifyDataType(value, fieldName: label),
                            confidence: 0.78,
                            extractedFrom: "clipboard",
                            alternatives: nil
                        )
                    },
                    provenanceEvents: ["event\(index)"]
                ))
            }
        }

        return entityId
    }

    private static func parseClipboardValue(_ text: String) -> [(String, String)] {
        var results: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            // Key: Value
            if let colonRange = line.range(of: ":") {
                let key = line[..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    results.append((key.lowercased(), value))
                }
                continue
            }

            // Tab separated
            let tabs = line.components(separatedBy: "\t").filter { !$0.isEmpty }
            if tabs.count >= 2 {
                for value in tabs {
                    let clean = value.trimmingCharacters(in: .whitespaces)
                    let dataType = classifyDataType(clean, fieldName: clean)
                    results.append((dataType.rawValue, clean))
                }
                continue
            }

            // Standalone value
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.count > 3 && clean.count < 200 {
                let dataType = classifyDataType(clean, fieldName: clean)
                results.append((dataType.rawValue, clean))
            }
        }

        return results
    }

    // MARK: - Typed Text Entity Extraction

    private static func extractTypedTextEntities(
        events: [EventTapManager.CapturedEvent],
        actions: [SemanticAction],
        entities: inout [EntityNode],
        startId: Int
    ) -> Int {
        var entityId = startId

        for action in actions where action.action == "type_text" || action.action == "fill_form" {
            guard let text = action.payload.typedText, text.count > 3 else { continue }

            entityId += 1
            entities.append(EntityNode(
                id: "entity\(entityId)",
                entityType: .textBlock,
                category: .extractedValue,
                name: "Typed Text",
                source: EntityNode.EntitySource(
                    application: action.provider,
                    url: action.payload.url,
                    artifactId: nil,
                    extractionMethod: "typed_text"
                ),
                confidence: 0.75,
                fields: [
                    EntityNode.EntityField(
                        name: "content",
                        value: text,
                        dataType: .freeText,
                        confidence: 0.75,
                        extractedFrom: "typed_text",
                        alternatives: nil
                    )
                ],
                provenanceEvents: []
            ))
        }

        return entityId
    }

    // MARK: - Helper: data type → entity type

    private static func dataTypeToEntityType(_ dt: EntityNode.FieldDataType) -> EntityType {
        switch dt {
        case .currencyAmount: return .currencyAmount
        case .date: return .date
        case .emailAddress: return .emailAddress
        case .phoneNumber: return .phoneNumber
        case .personName: return .personName
        case .companyName: return .companyName
        case .address: return .address
        case .identifier: return .identifier
        case .url: return .url
        default: return .textBlock
        }
    }

    private static func inferDomain(from fields: [(String, String)]) -> String {
        let text = fields.map { "\($0.0) \($0.1)" }.joined(separator: " ").lowercased()
        if text.contains("invoice") || text.contains("bill") || text.contains("vendor") { return "accounts_payable" }
        if text.contains("lead") || text.contains("linkedin") { return "lead_generation" }
        if text.contains("expense") || text.contains("receipt") { return "expense_management" }
        return "general"
    }

    private static func entityTypeForDomain(_ domain: String) -> EntityType {
        switch domain {
        case "accounts_payable": return .invoice
        case "lead_generation": return .lead
        case "expense_management": return .expense
        case "crm": return .contact
        default: return .file
        }
    }

    // MARK: - Step 2: Relationship Extraction

    private static func extractRelationships(
        from entities: [EntityNode],
        actions: [SemanticAction],
        artifacts: [ExtractedArtifact]
    ) -> [EntityRelationship] {
        var relationships: [EntityRelationship] = []
        var relId = 0

        // Artifact links → entity relationships
        for artifact in artifacts {
            let entityId = "entity\(artifacts.firstIndex(where: { $0.id == artifact.id })! + 1)"
            for rel in artifact.relationships {
                guard let targetIdx = artifacts.firstIndex(where: { $0.id == rel.targetArtifactId }) else { continue }
                let targetId = "entity\(targetIdx + 1)"

                let relType: EntityRelationship.RelationshipType
                switch rel.relationship {
                case "derived_from": relType = .derives
                case "updates": relType = .references
                case "contains": relType = .contains
                case "related": relType = .references
                default: relType = .references
                }

                relId += 1
                relationships.append(EntityRelationship(
                    id: "rel\(relId)",
                    sourceEntityId: entityId,
                    targetEntityId: targetId,
                    relationshipType: relType,
                    confidence: 0.75,
                    metadata: .init(
                        transformation: rel.relationship == "derived_from" ? "extract" : nil,
                        evidence: ["artifact_relationship"]
                    )
                ))
            }
        }

        // Entity containment: documents contain extracted values
        let docs = entities.filter { $0.category == .document }
        let values = entities.filter { $0.category == .extractedValue }
        for doc in docs {
            for val in values where val.source.application == doc.source.application {
                relId += 1
                relationships.append(EntityRelationship(
                    id: "rel\(relId)",
                    sourceEntityId: doc.id,
                    targetEntityId: val.id,
                    relationshipType: .contains,
                    confidence: 0.65,
                    metadata: .init(
                        evidence: ["same_application", "temporal_proximity"]
                    )
                ))
            }
        }

        // Business objects contain extracted values
        let bizObjs = entities.filter { $0.category == .businessObject }
        for biz in bizObjs {
            for val in values where biz.fields.map({ $0.value }).contains(val.fields.first?.value ?? "") {
                relId += 1
                relationships.append(EntityRelationship(
                    id: "rel\(relId)",
                    sourceEntityId: biz.id,
                    targetEntityId: val.id,
                    relationshipType: .contains,
                    confidence: 0.80,
                    metadata: .init(
                        evidence: ["value_match"]
                    )
                ))
            }
        }

        return relationships
    }

    // MARK: - Step 3: Field Mapping Detection (clipboard → paste correlation)

    private static func detectFieldMappings(
        from events: [EventTapManager.CapturedEvent],
        entities: [EntityNode],
        actions: [SemanticAction]
    ) -> [FieldMapping] {
        var mappings: [FieldMapping] = []
        var mapId = 0

        // Key insight: clipboard copy followed by type_text within a short window = field mapping
        var lastClipboardValues: [(value: String, eventIndex: Int, timestamp: Double)] = []

        for (index, event) in events.enumerated() {
            // Track clipboard changes
            if event.type == "clipboardChange", let clip = event.clipboardSnapshot, !clip.isEmpty {
                lastClipboardValues.append((value: clip, eventIndex: index, timestamp: event.timestamp))
                // Keep only last 5 clipboard entries
                if lastClipboardValues.count > 5 { lastClipboardValues.removeFirst() }
            }

            // When user types after copying, detect mapping
            if event.type == "keyDown", let chars = event.characters, event.redacted != true {
                let typedValue = extractMeaningfulValue(chars, from: events, around: index)

                // Check if this typed value matches any recent clipboard value
                for clip in lastClipboardValues {
                    let similarity = stringSimilarity(typedValue, clip.value)
                    let timeDelta = event.timestamp - clip.timestamp

                    // Match if: high similarity OR exact match, within 30 seconds
                    if similarity > 0.85 || (typedValue == clip.value && timeDelta < 30) {
                        let sourceEntity = findEntity(containing: clip.value, in: entities)
                        let targetAction = findAction(around: index, in: actions)

                        if let srcEnt = sourceEntity {
                            mapId += 1
                            let sourceField = srcEnt.fields.first(where: { $0.value == clip.value })
                            mappings.append(FieldMapping(
                                id: "map\(mapId)",
                                sourceEntityId: srcEnt.id,
                                sourceFieldName: sourceField?.name ?? "unknown",
                                targetEntityId: "entity\(entities.count + 1)", // will be resolved
                                targetFieldName: inferTargetField(from: targetAction, in: entities),
                                mappingType: similarity >= 0.95 ? .directCopy : .copyAndFormat,
                                confidence: min(similarity + (timeDelta < 5 ? 0.10 : 0), 1.0),
                                metadata: FieldMapping.MappingMetadata(
                                    sourceValue: clip.value,
                                    targetValue: typedValue,
                                    clipboardMatch: true,
                                    headerMatch: false,
                                    valueSimilarity: similarity,
                                    temporalProximity: timeDelta
                                )
                            ))
                        }
                    }
                }
            }
        }

        // Infer mappings from field name similarity (spreadsheet headers)
        let spreadsheetEntities = entities.filter { $0.entityType == .spreadsheet }
        for sheet in spreadsheetEntities {
            for other in entities where other.id != sheet.id {
                for sheetField in sheet.fields {
                    for otherField in other.fields {
                        let similarity = stringSimilarity(sheetField.name, otherField.name)
                        if similarity > 0.70 {
                            mapId += 1
                            mappings.append(FieldMapping(
                                id: "map\(mapId)",
                                sourceEntityId: other.id,
                                sourceFieldName: otherField.name,
                                targetEntityId: sheet.id,
                                targetFieldName: sheetField.name,
                                mappingType: .inferred,
                                confidence: similarity,
                                metadata: FieldMapping.MappingMetadata(
                                    sourceValue: nil,
                                    targetValue: nil,
                                    clipboardMatch: false,
                                    headerMatch: true,
                                    valueSimilarity: similarity,
                                    temporalProximity: nil
                                )
                            ))
                        }
                    }
                }
            }
        }

        return mappings
    }

    private static func extractMeaningfulValue(_ chars: String, from events: [EventTapManager.CapturedEvent], around index: Int) -> String {
        // Collect a burst of keystrokes around this event (the full typed value)
        var buffer = chars
        let window = 10 // events before/after

        for i in max(0, index - window)..<min(events.count, index + window) {
            if events[i].type == "keyDown", let c = events[i].characters, events[i].redacted != true {
                if c == "\r" || c == "\n" { break }
                if !buffer.contains(c) || events[i].timestamp - events[index].timestamp < 2.0 {
                    if events[i].timestamp >= events[index].timestamp && i != index {
                        buffer += c
                    }
                }
            }
        }

        return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringSimilarity(_ a: String, _ b: String) -> Double {
        let cleanA = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanB = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return 0 }

        if cleanA == cleanB { return 1.0 }
        if cleanB.contains(cleanA) || cleanA.contains(cleanB) { return 0.90 }

        // Levenshtein ratio
        let dist = levenshteinDistance(cleanA, cleanB)
        let maxLen = Double(max(cleanA.count, cleanB.count))
        return maxLen > 0 ? max(0, 1.0 - Double(dist) / maxLen) : 0
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aCount = a.count, bCount = b.count
        guard aCount > 0 else { return bCount }
        guard bCount > 0 else { return aCount }

        var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)
        for i in 0...aCount { matrix[i][0] = i }
        for j in 0...bCount { matrix[0][j] = j }

        let aChars = Array(a), bChars = Array(b)
        for i in 1...aCount {
            for j in 1...bCount {
                matrix[i][j] = aChars[i - 1] == bChars[j - 1]
                    ? matrix[i - 1][j - 1]
                    : min(matrix[i - 1][j], matrix[i][j - 1], matrix[i - 1][j - 1]) + 1
            }
        }

        return matrix[aCount][bCount]
    }

    private static func findEntity(containing value: String, in entities: [EntityNode]) -> EntityNode? {
        entities.first { entity in
            entity.fields.contains { $0.value.contains(value) || value.contains($0.value) }
        }
    }

    private static func findAction(around eventIndex: Int, in actions: [SemanticAction]) -> SemanticAction? {
        // Return the semantic action that corresponds to this event region
        // Simplified: return the first type_text or fill_form action
        actions.first { $0.action == "type_text" || $0.action == "fill_form" }
    }

    private static func inferTargetField(from action: SemanticAction?, in entities: [EntityNode]) -> String {
        guard let action = action else { return "unknown" }
        // If action appends to sheet, target field is a sheet column
        if action.action == "sheets_append", let values = action.payload.values, !values.isEmpty {
            return values.joined(separator: ", ")
        }
        return action.description
    }

    // MARK: - Step 4: Data Lineage Tracking

    private static func buildLineagePaths(
        from entities: [EntityNode],
        relationships: [EntityRelationship],
        mappings: [FieldMapping]
    ) -> [DataLineagePath] {
        var paths: [DataLineagePath] = []
        var pathId = 0

        // Build lineage from document → business object → extracted field → destination

        // Path type 1: Email → attachment → extracted value
        for rel in relationships where rel.relationshipType == .contains {
            guard let source = entities.first(where: { $0.id == rel.sourceEntityId }),
                  let target = entities.first(where: { $0.id == rel.targetEntityId }),
                  source.category == .document else { continue }

            pathId += 1
            paths.append(DataLineagePath(
                id: "lineage\(pathId)",
                description: "\(source.name) contains \(target.name)",
                nodes: [
                    .init(entityId: source.id, entityName: source.name, entityType: source.entityType.rawValue, transformation: nil),
                    .init(entityId: target.id, entityName: target.name, entityType: target.entityType.rawValue, transformation: "extract"),
                ],
                confidence: rel.confidence * 0.9
            ))
        }

        // Path type 2: Clipboard value → typed text (mapping backed)
        for mapping in mappings where mapping.metadata.clipboardMatch == true {
            guard let source = entities.first(where: { $0.id == mapping.sourceEntityId }) else { continue }

            pathId += 1
            paths.append(DataLineagePath(
                id: "lineage\(pathId)",
                description: "\(source.name).\(mapping.sourceFieldName) → \(mapping.targetFieldName)",
                nodes: [
                    .init(entityId: source.id, entityName: source.name, entityType: source.entityType.rawValue, transformation: nil),
                    .init(entityId: "clipboard", entityName: mapping.sourceFieldName, entityType: "ExtractedValue", transformation: "copy"),
                    .init(entityId: "destination", entityName: mapping.targetFieldName, entityType: "Spreadsheet", transformation: mapping.mappingType == .directCopy ? "paste" : "format"),
                ],
                confidence: mapping.confidence
            ))
        }

        // Path type 3: Full chain — deduce from entities + relationships
        let docs = entities.filter { $0.category == .document }
        let bizObjs = entities.filter { $0.category == .businessObject }
        let values = entities.filter { $0.category == .extractedValue }

        if let doc = docs.first, let biz = bizObjs.first {
            var nodes: [DataLineagePath.LineageNode] = [
                .init(entityId: doc.id, entityName: doc.name, entityType: doc.entityType.rawValue, transformation: nil)
            ]

            // Find values that belong to this business object
            let relatedValues = values.filter { val in
                biz.fields.contains { $0.value.contains(val.fields.first?.value ?? "") }
            }

            if !relatedValues.isEmpty {
                nodes.append(.init(entityId: biz.id, entityName: biz.name, entityType: biz.entityType.rawValue, transformation: "extract"))
                for val in relatedValues {
                    nodes.append(.init(entityId: val.id, entityName: val.fields.first?.name ?? val.name, entityType: val.entityType.rawValue, transformation: "derive"))
                }

                // Find destination (spreadsheet)
                if let sheet = entities.first(where: { $0.entityType == .spreadsheet }) {
                    nodes.append(.init(entityId: sheet.id, entityName: sheet.name, entityType: "Spreadsheet", transformation: "write"))

                    pathId += 1
                    paths.append(DataLineagePath(
                        id: "lineage\(pathId)",
                        description: "\(doc.entityType.rawValue) → \(biz.entityType.rawValue) → Spreadsheet",
                        nodes: nodes,
                        confidence: 0.70
                    ))
                }
            }
        }

        return paths
    }

    // MARK: - Step 5: Confidence

    private static func computeConfidence(
        entities: [EntityNode],
        relationships: [EntityRelationship],
        mappings: [FieldMapping],
        lineage: [DataLineagePath]
    ) -> EntityGraph.EntityGraphConfidence {
        let entityConf = entities.isEmpty ? 0 : entities.map(\.confidence).reduce(0, +) / Double(entities.count)
        let relConf = relationships.isEmpty ? 0 : relationships.map(\.confidence).reduce(0, +) / Double(relationships.count)
        let mapConf = mappings.isEmpty ? 0 : mappings.map(\.confidence).reduce(0, +) / Double(mappings.count)
        let lineageConf = lineage.isEmpty ? 0 : lineage.map(\.confidence).reduce(0, +) / Double(lineage.count)

        let overall = entityConf * 0.25 + relConf * 0.20 + mapConf * 0.30 + lineageConf * 0.25

        return EntityGraph.EntityGraphConfidence(
            entityConfidence: entityConf,
            relationshipConfidence: relConf,
            mappingConfidence: mapConf,
            lineageConfidence: lineageConf,
            overallConfidence: overall
        )
    }

    // MARK: - JSON Serialization

    static func toJSON(_ graph: EntityGraph) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(graph),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - AI Prompt Summary

    static func buildEntityGraphSummary(from graph: EntityGraph) -> String {
        var lines: [String] = []
        lines.append("## Entity Graph — Data Understanding Layer")
        lines.append("Confidence: \(Int(graph.confidence.overallConfidence * 100))%")
        lines.append("")

        if !graph.entities.isEmpty {
            lines.append("### Entities (\(graph.entities.count))")
            for entity in graph.entities {
                let cat = entity.category.rawValue
                lines.append("")
                lines.append("**\(entity.id): \(entity.name)** [\(entity.entityType.rawValue)] · \(cat) · \(Int(entity.confidence * 100))%")
                lines.append("  Source: \(entity.source.application) via \(entity.source.extractionMethod)")
                if !entity.fields.isEmpty {
                    lines.append("  Fields:")
                    for field in entity.fields {
                        lines.append("    - \(field.name): \(field.value) (\(field.dataType.rawValue))")
                    }
                }
            }
            lines.append("")
        }

        if !graph.relationships.isEmpty {
            lines.append("### Relationships (\(graph.relationships.count))")
            for rel in graph.relationships {
                let src = graph.entities.first(where: { $0.id == rel.sourceEntityId })?.name ?? rel.sourceEntityId
                let tgt = graph.entities.first(where: { $0.id == rel.targetEntityId })?.name ?? rel.targetEntityId
                lines.append("- \(src) → \(tgt) [\(rel.relationshipType.rawValue)] (\(Int(rel.confidence * 100))%)")
            }
            lines.append("")
        }

        if !graph.fieldMappings.isEmpty {
            lines.append("### Field Mappings (\(graph.fieldMappings.count))")
            for mapping in graph.fieldMappings {
                let evidence = [
                    mapping.metadata.clipboardMatch == true ? "clipboard" : nil,
                    mapping.metadata.headerMatch == true ? "headers" : nil,
                ].compactMap { $0 }.joined(separator: "+")
                lines.append("- \(mapping.sourceFieldName) → \(mapping.targetFieldName) [\(mapping.mappingType.rawValue)] (\(Int(mapping.confidence * 100))%) evidence: \(evidence)")
                if let sim = mapping.metadata.valueSimilarity {
                    lines.append("  similarity: \(Int(sim * 100))%")
                }
            }
            lines.append("")
        }

        if !graph.lineagePaths.isEmpty {
            lines.append("### Data Lineage (\(graph.lineagePaths.count))")
            for path in graph.lineagePaths {
                lines.append("- \(path.description) (\(Int(path.confidence * 100))%)")
                let chain = path.nodes.map { $0.entityName }.joined(separator: " → ")
                lines.append("  \(chain)")
            }
            lines.append("")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }
}
