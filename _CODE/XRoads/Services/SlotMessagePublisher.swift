import Foundation
import GRDB
import os

// MARK: - SlotMessagePublisher

/// Bridges PTY stdout output to the MessageBusService.
/// Parses [XROADS:{...}] lines and publishes them as AgentMessages.
/// Updates AgentSlot.currentTask on status messages.
actor SlotMessagePublisher {

    private let logger = Logger(subsystem: "com.xroads", category: "SlotMessagePublisher")
    private let parser = PTYOutputParser()
    private let bus: MessageBusService
    private let dbQueue: DatabaseQueue

    init(bus: MessageBusService, dbQueue: DatabaseQueue) {
        self.bus = bus
        self.dbQueue = dbQueue
    }

    // MARK: - Public

    /// Process a chunk of PTY stdout text for a given slot.
    /// Extracts [XROADS:{...}] payloads, publishes them as AgentMessages,
    /// and updates AgentSlot.currentTask on status messages.
    func processOutput(text: String, slotId: UUID) async {
        let payloads = parser.parseAll(text: text)
        guard !payloads.isEmpty else { return }

        for payload in payloads {
            guard let messageType = AgentMessageType(rawValue: payload.type) else {
                let rawType = payload.type
                logger.warning("Unknown XROADS message type: \(rawType)")
                continue
            }

            let message = AgentMessage(
                content: payload.content,
                messageType: messageType,
                fromSlotId: slotId,
                isBroadcast: true
            )

            do {
                try await bus.publish(message: message, fromSlot: slotId)
            } catch {
                let errorDesc = error.localizedDescription
                logger.error("Failed to publish message: \(errorDesc)")
            }

            // Update currentTask on status messages
            if messageType == .status {
                do {
                    try updateCurrentTask(slotId: slotId, task: payload.content)
                } catch {
                    let errorDesc = error.localizedDescription
                    logger.error("Failed to update currentTask: \(errorDesc)")
                }
            }
        }
    }

    // MARK: - Private

    private func updateCurrentTask(slotId: UUID, task: String) throws {
        try dbQueue.write { db in
            guard var slot = try AgentSlot.fetchOne(db, key: slotId) else { return }
            slot.currentTask = task
            slot.updatedAt = Date()
            try slot.update(db)
        }
    }
}
