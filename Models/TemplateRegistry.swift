import Foundation

struct TemplateRegistryEntry {
    let id: String
    let shortTitle: String
    let sortOrder: Int
    let usageBullets: [String]
}

enum TemplateRegistry {
    static let entries: [TemplateRegistryEntry] = [
        TemplateRegistryEntry(
            id: "symmetry",
            shortTitle: "Symmetry",
            sortOrder: 0,
            usageBullets: [
                "Find mirrored shapes or reflections.",
                "Keep the center line precise.",
                "Reduce distractions at the edges."
            ]
        ),
        TemplateRegistryEntry(
            id: "center",
            shortTitle: "Center",
            sortOrder: 1,
            usageBullets: [
                "Use strong symmetry for impact.",
                "Keep edges clean and balanced.",
                "Let the subject dominate the frame."
            ]
        ),
        TemplateRegistryEntry(
            id: "leading_lines",
            shortTitle: "Leading Lines",
            sortOrder: 2,
            usageBullets: [
                "Use lines to direct attention.",
                "Keep lines clean and intentional.",
                "Let lines converge on the subject."
            ]
        ),
        TemplateRegistryEntry(
            id: "golden_spiral",
            shortTitle: "Spiral",
            sortOrder: 3,
            usageBullets: [
                "Guide the eye along the spiral curve.",
                "Position the focal point at the spiral core.",
                "Keep the flow unobstructed."
            ]
        ),
        TemplateRegistryEntry(
            id: "framing",
            shortTitle: "Framing",
            sortOrder: 4,
            usageBullets: [
                "Use foreground elements as a frame.",
                "Keep the subject inside the window.",
                "Balance frame weight on both sides."
            ]
        ),
        TemplateRegistryEntry(
            id: "diagonals",
            shortTitle: "Diagonals",
            sortOrder: 5,
            usageBullets: [
                "Align the main structure along a diagonal.",
                "Use diagonals to create motion and tension.",
                "Keep the diagonal clean and dominant."
            ]
        ),
        TemplateRegistryEntry(
            id: "negative_space",
            shortTitle: "Negative Space",
            sortOrder: 6,
            usageBullets: [
                "Give the subject room to breathe.",
                "Use emptiness to emphasize form.",
                "Simplify the background."
            ]
        ),
        TemplateRegistryEntry(
            id: "portrait_headroom",
            shortTitle: "Headroom",
            sortOrder: 7,
            usageBullets: [
                "Keep eyes near the eye-line guide.",
                "Leave clean headroom above the subject.",
                "Avoid cramped framing at the top."
            ]
        ),
        TemplateRegistryEntry(
            id: "triangle",
            shortTitle: "Triangle",
            sortOrder: 8,
            usageBullets: [
                "Build a clear triangle with subject elements.",
                "Use the apex as the attention anchor.",
                "Keep the base stable and uncluttered."
            ]
        ),
        TemplateRegistryEntry(
            id: "layers_fmb",
            shortTitle: "Layers",
            sortOrder: 9,
            usageBullets: [
                "Include a foreground element for depth.",
                "Place the main subject in the midground.",
                "Use background to set context, not clutter."
            ]
        ),
        TemplateRegistryEntry(
            id: "rule_of_thirds",
            shortTitle: "Thirds",
            sortOrder: 10,
            usageBullets: [
                "Place the subject near intersecting thirds.",
                "Align horizon on upper or lower third.",
                "Avoid centering unless intentional."
            ]
        )
    ]

    static let entriesByID: [String: TemplateRegistryEntry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.id, $0) }
    )

    static let supportedIDs: Set<String> = Set(entries.map(\.id))

    static func shortTitle(for templateID: String, fallback: String) -> String {
        entriesByID[templateID]?.shortTitle ?? fallback
    }

    static func sortIndex(for templateID: String) -> Int? {
        entriesByID[templateID]?.sortOrder
    }

    static func usageBullets(for templateID: String) -> [String]? {
        entriesByID[templateID]?.usageBullets
    }
}
