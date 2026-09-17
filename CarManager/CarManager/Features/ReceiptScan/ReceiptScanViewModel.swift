import Foundation
import Observation

@MainActor
@Observable
final class ReceiptScanViewModel {
    private(set) var scanState: ReceiptScanState = .capturing
    var acceptedTotal = false
    var acceptedDate = false

    private let vehicleID: VehicleID
    private let scanReceipt: ScanReceipt
    private let confirmReceiptScan: ConfirmReceiptScan
    private let clock: any ClockProviding
    private var task: Task<Void, Never>?

    init(
        vehicleID: VehicleID, scanReceipt: ScanReceipt,
        confirmReceiptScan: ConfirmReceiptScan, clock: any ClockProviding
    ) {
        self.vehicleID = vehicleID
        self.scanReceipt = scanReceipt
        self.confirmReceiptScan = confirmReceiptScan
        self.clock = clock
    }

    var canConfirm: Bool { acceptedTotal && acceptedDate }

    func capture() {
        // Placeholder image — the real camera arrives with the UI stage.
        let placeholder = Data("placeholder-receipt".utf8)
        scanState = .analyzing(imageRef: FileRef(relativePath: "pending"))
        task = Task {
            do {
                // ScanReceipt STOPS at .awaitingReview. It holds no financial repository,
                // so it cannot write a record even if it wanted to.
                let scan = try await scanReceipt(imageData: placeholder, vehicleID: vehicleID)
                scanState = .awaitingReview(scan)
            } catch {
                scanState = .failed(message: String(describing: error), retryable: true)
            }
        }
    }

    func confirm() async {
        guard case .awaitingReview(var scan) = scanState else { return }

        // The user's acceptance is recorded on the draft itself.
        scan.draft.total.isAccepted = acceptedTotal
        scan.draft.date.isAccepted = acceptedDate
        scanState = .confirming(scan)

        // ConfirmedReceipt is failable: it returns nil unless every required field has been
        // accepted by a human. Saving without confirmation is unrepresentable.
        guard let confirmed = ConfirmedReceipt(reviewing: scan, at: clock.now) else {
            scanState = .awaitingReview(scan)
            return
        }

        do {
            let ref = try await confirmReceiptScan(confirmed)
            scanState = .saved(ref)
        } catch {
            scanState = .failed(message: String(describing: error), retryable: true)
        }
    }

    func discard() {
        task?.cancel()
        scanState = .discarded
    }

    func reset() {
        acceptedTotal = false
        acceptedDate = false
        scanState = .capturing
    }
}
