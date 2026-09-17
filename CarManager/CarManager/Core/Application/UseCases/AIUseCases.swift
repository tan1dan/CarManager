import Foundation

// MARK: - Chat

public struct AskAI: Sendable {
    let conversations: any AIConversationRepository
    let provider: any AIProvider
    let buildContext: BuildAIContext
    let clock: any ClockProviding

    public init(
        conversations: any AIConversationRepository, provider: any AIProvider,
        buildContext: BuildAIContext, clock: any ClockProviding
    ) {
        self.conversations = conversations; self.provider = provider
        self.buildContext = buildContext; self.clock = clock
    }

    public struct Input: Sendable {
        public let conversationID: ConversationID?
        public let vehicleID: VehicleID?
        public let text: String
        public init(conversationID: ConversationID?, vehicleID: VehicleID?, text: String) {
            self.conversationID = conversationID; self.vehicleID = vehicleID; self.text = text
        }
    }

    public enum Event: Sendable {
        case conversationCreated(ConversationID)
        case userMessageSaved(AIMessage)
        case delta(String)
        case assistantCompleted(AIMessage)
    }

    public func callAsFunction(_ input: Input) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let now = clock.now

                    // Resolve or create the conversation.
                    let conversationID: ConversationID
                    if let existing = input.conversationID {
                        conversationID = existing
                    } else {
                        let created = AIConversation(
                            vehicleID: input.vehicleID,
                            title: String(input.text.prefix(40)),
                            createdAt: now, updatedAt: now
                        )
                        try await conversations.create(created)
                        conversationID = created.id
                        continuation.yield(.conversationCreated(conversationID))
                    }

                    // The user message is persisted BEFORE the request — a crash or a cancel
                    // must never lose what the user typed.
                    let userMessage = AIMessage(role: .user, text: input.text, createdAt: now)
                    try await conversations.appendMessage(userMessage, to: conversationID)
                    continuation.yield(.userMessageSaved(userMessage))

                    // A bounded snapshot, never raw rows. Absent for general questions.
                    var resolvedContext: AIVehicleContext?
                    if let vehicleID = input.vehicleID {
                        resolvedContext = try? await buildContext(vehicleID: vehicleID)
                    }

                    let history = try await conversations.conversation(id: conversationID)?.messages ?? []
                    let request = AIChatRequest(
                        messages: history, context: resolvedContext, purpose: .chat
                    )

                    // Deltas accumulate in memory. They are NEVER persisted per token —
                    // that would produce hundreds of writes (and CloudKit records) per answer.
                    var buffer = ""
                    for try await event in provider.stream(request) {
                        try Task.checkCancellation()
                        switch event {
                        case .delta(let chunk):
                            buffer += chunk
                            continuation.yield(.delta(chunk))
                        case .completed(let text):
                            buffer = text.isEmpty ? buffer : text
                        }
                    }

                    let assistantMessage = AIMessage(
                        role: .assistant, text: buffer, isPartial: false, createdAt: clock.now
                    )
                    try await conversations.appendMessage(assistantMessage, to: conversationID)
                    continuation.yield(.assistantCompleted(assistantMessage))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DomainError.ai(.cancelled))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct LoadConversation: Sendable {
    let conversations: any AIConversationRepository
    public init(conversations: any AIConversationRepository) { self.conversations = conversations }
    public func callAsFunction(id: ConversationID) async throws -> AIConversation? {
        try await conversations.conversation(id: id)
    }
}

public struct ListConversations: Sendable {
    let conversations: any AIConversationRepository
    public init(conversations: any AIConversationRepository) { self.conversations = conversations }
    public func callAsFunction(vehicleID: VehicleID?) async throws -> [ConversationSummary] {
        try await conversations.summaries(vehicleID: vehicleID)
    }
}

public struct DeleteConversation: Sendable {
    let conversations: any AIConversationRepository
    public init(conversations: any AIConversationRepository) { self.conversations = conversations }
    public func callAsFunction(id: ConversationID) async throws {
        _ = try await conversations.delete(id: id)
    }
}

/// Assembles a bounded, deterministic snapshot. The raw database is never sent to the model.
public struct BuildAIContext: Sendable {
    let vehicles: any VehicleRepository
    let odometer: any OdometerRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let expenses: any ExpenseRepository
    let clock: any ClockProviding

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository,
        fuel: any FuelRepository, services: any ServiceRepository,
        expenses: any ExpenseRepository, clock: any ClockProviding
    ) {
        self.vehicles = vehicles; self.odometer = odometer; self.fuel = fuel
        self.services = services; self.expenses = expenses; self.clock = clock
    }

    public func callAsFunction(vehicleID: VehicleID) async throws -> AIVehicleContext {
        guard let vehicle = try await vehicles.vehicle(id: vehicleID) else {
            throw DomainError.validation(.vehicleNotFound)
        }
        let current = try await odometer.current(vehicleID: vehicleID)
        let fuelEntries = try await fuel.entries(vehicleID: vehicleID)
        let serviceCount = try await services.count(vehicleID: vehicleID)
        let expenseList = try await expenses.expenses(vehicleID: vehicleID)
        let fullTankCount = fuelEntries.filter(\.isFullTank).count

        return AIVehicleContext(
            generatedAt: clock.now,
            // Note what is NOT copied across: VIN, plate, colour, notes, workshop names.
            // Redaction is structural — VehicleFacts has no field to hold them.
            vehicle: .init(
                brand: vehicle.brand, model: vehicle.model, year: vehicle.year,
                fuelType: vehicle.fuelType.rawValue,
                currentOdometerKm: current?.value.kilometers
            ),
            coverage: .init(
                fuelEntryCount: fuelEntries.count,
                serviceRecordCount: serviceCount,
                expenseCount: expenseList.count,
                hasSufficientDataForConsumption: fullTankCount >= 2
            )
        )
    }
}

// MARK: - Receipt scan

/// Reaches `.awaitingReview` and STOPS. It holds no financial repository, so it is not merely
/// discouraged from saving a record — it is incapable of it.
public struct ScanReceipt: Sendable {
    let vision: any VisionAnalysisProvider
    let textRecognizer: any TextRecognizing
    let preprocessor: any ImagePreprocessing
    let files: any FileStorage
    let scans: any ScanRepository
    let clock: any ClockProviding

    public init(
        vision: any VisionAnalysisProvider, textRecognizer: any TextRecognizing,
        preprocessor: any ImagePreprocessing, files: any FileStorage,
        scans: any ScanRepository, clock: any ClockProviding
    ) {
        self.vision = vision; self.textRecognizer = textRecognizer
        self.preprocessor = preprocessor; self.files = files
        self.scans = scans; self.clock = clock
    }

    public func callAsFunction(imageData: Data, vehicleID: VehicleID) async throws -> ReceiptScan {
        // EXIF/GPS are stripped before anything leaves the device.
        let prepared = try await preprocessor.prepareForUpload(imageData)
        let ref = try await files.store(prepared, preferredName: "receipt", kind: .receipt)
        // On-device OCR first: fewer tokens, better accuracy, and an offline audit trail.
        let ocrText = try? await textRecognizer.recognizeText(in: prepared)

        let result = try await vision.analyze(
            .receipt(image: prepared, ocrText: ocrText, vehicleID: vehicleID)
        )
        guard case .receipt(let draft) = result else {
            throw DomainError.ai(.structuredOutputInvalid)
        }

        let scan = ReceiptScan(
            vehicleID: vehicleID, imageRef: ref, recognizedText: ocrText,
            draft: draft, status: .awaitingReview, createdAt: clock.now
        )
        try await scans.upsert(scan)
        return scan
    }
}

/// The ONLY path from a scan to a persisted record. Its input type cannot be constructed
/// without a human review pass.
public struct ConfirmReceiptScan: Sendable {
    let addFuel: AddFuelEntry
    let addService: AddServiceRecord
    let addExpense: AddExpense
    let scans: any ScanRepository

    public init(
        addFuel: AddFuelEntry, addService: AddServiceRecord,
        addExpense: AddExpense, scans: any ScanRepository
    ) {
        self.addFuel = addFuel; self.addService = addService
        self.addExpense = addExpense; self.scans = scans
    }

    public func callAsFunction(_ confirmed: ConfirmedReceipt) async throws -> RecordRef {
        // Idempotent: confirming an already-confirmed scan returns the existing record.
        if let existing = try await scans.receiptScan(id: confirmed.scanID),
           case .confirmed(let ref) = existing.status {
            return ref
        }

        // EXACTLY ONE record is written, of exactly one kind. Never two.
        let ref: RecordRef
        switch confirmed.kind {
        case .fuel:
            let output = try await addFuel(FuelEntryDraft(
                vehicleID: confirmed.vehicleID, date: confirmed.date,
                odometer: confirmed.odometer ?? Odometer(kilometers: 0),
                volume: confirmed.fuelVolume ?? Volume(liters: 0),
                totalCost: confirmed.total, fuelType: .petrol,
                station: confirmed.vendor, source: .receiptScan(confirmed.scanID)
            ))
            ref = .fuel(output.entry.id)

        case .service:
            let items = confirmed.serviceItems.isEmpty
                ? [ServiceItem(type: .other, name: confirmed.vendor ?? "Service")]
                : confirmed.serviceItems
            let output = try await addService(
                vehicleID: confirmed.vehicleID, date: confirmed.date,
                odometerValue: confirmed.odometer, items: items,
                workshop: confirmed.vendor, totalCost: confirmed.total,
                source: .receiptScan(confirmed.scanID)
            )
            ref = .service(output.record.id)

        case .expense:
            let expense = try await addExpense(
                vehicleID: confirmed.vehicleID,
                title: confirmed.vendor ?? "Expense",
                category: confirmed.expenseCategory, cost: confirmed.total,
                date: confirmed.date, odometerValue: confirmed.odometer,
                source: .receiptScan(confirmed.scanID)
            )
            ref = .expense(expense.id)
        }

        if var scan = try await scans.receiptScan(id: confirmed.scanID) {
            scan.status = .confirmed(ref)
            try await scans.upsert(scan)
        }
        return ref
    }
}

// MARK: - Vision scans

public struct ScanDashboard: Sendable {
    let vision: any VisionAnalysisProvider
    let preprocessor: any ImagePreprocessing
    let files: any FileStorage
    let scans: any ScanRepository
    let clock: any ClockProviding

    public init(
        vision: any VisionAnalysisProvider, preprocessor: any ImagePreprocessing,
        files: any FileStorage, scans: any ScanRepository, clock: any ClockProviding
    ) {
        self.vision = vision; self.preprocessor = preprocessor
        self.files = files; self.scans = scans; self.clock = clock
    }

    public func callAsFunction(imageData: Data, vehicleID: VehicleID?) async throws -> DashboardScan {
        let prepared = try await preprocessor.prepareForUpload(imageData)
        let ref = try await files.store(prepared, preferredName: "dashboard", kind: .scan)
        let result = try await vision.analyze(.dashboard(image: prepared, vehicleID: vehicleID))
        guard case .dashboard(let findings) = result else {
            throw DomainError.ai(.structuredOutputInvalid)
        }
        // The disclaimer is non-optional on the result type: a result without one is
        // unrepresentable. No vehicle record is created from a scan.
        let scan = DashboardScan(
            vehicleID: vehicleID, imageRef: ref, findings: findings, createdAt: clock.now
        )
        try await scans.insert(scan)
        return scan
    }
}

public struct AnalyzeDamage: Sendable {
    let vision: any VisionAnalysisProvider
    let preprocessor: any ImagePreprocessing
    let files: any FileStorage
    let scans: any ScanRepository
    let clock: any ClockProviding

    public init(
        vision: any VisionAnalysisProvider, preprocessor: any ImagePreprocessing,
        files: any FileStorage, scans: any ScanRepository, clock: any ClockProviding
    ) {
        self.vision = vision; self.preprocessor = preprocessor
        self.files = files; self.scans = scans; self.clock = clock
    }

    public func callAsFunction(imagesData: [Data], vehicleID: VehicleID) async throws -> DamageAnalysis {
        var refs: [FileRef] = []
        var prepared: [Data] = []
        for image in imagesData {
            let processed = try await preprocessor.prepareForUpload(image)
            prepared.append(processed)
            refs.append(try await files.store(processed, preferredName: "damage", kind: .scan))
        }
        let result = try await vision.analyze(.damage(images: prepared, vehicleID: vehicleID))
        guard case .damage(let findings) = result else {
            throw DomainError.ai(.structuredOutputInvalid)
        }
        // Findings carry a CostEstimateRange, never a scalar price.
        let analysis = DamageAnalysis(
            vehicleID: vehicleID, imageRefs: refs, findings: findings, createdAt: clock.now
        )
        try await scans.insert(analysis)
        return analysis
    }
}
