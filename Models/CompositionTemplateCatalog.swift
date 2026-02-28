import Foundation
import UIKit

protocol TemplateSortable {
    var id: String { get }
    var name: String { get }
}

struct CompositionTemplate: Identifiable, TemplateSortable {
    let id: String
    let name: String
    let subtitle: String
    let philosophy: String
    let examples: [String]
}

private struct TemplateDTO: Decodable {
    let id: String
    let name: String
    let subtitle: String
    let philosophy: String
    let examples: [String]?
}

enum TemplateCatalog {
    static func load() -> [CompositionTemplate] {
        cachedTemplates
    }

    static func resolvedExamples(templateID: String, explicit: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for name in explicit {
            guard !name.isEmpty else { continue }
            if seen.insert(name).inserted {
                result.append(name)
            }
        }

        var foundViaProbe = false
        for i in 1...12 {
            let name = "\(templateID)_\(String(format: "%02d", i))"
            if UIImage(named: name) != nil {
                foundViaProbe = true
                if seen.insert(name).inserted {
                    result.append(name)
                }
            } else if foundViaProbe {
                break
            }
        }

        return result
    }

    private static let cachedTemplates: [CompositionTemplate] = {
        guard let url = Bundle.main.url(forResource: "templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dtos = try? JSONDecoder().decode([TemplateDTO].self, from: data) else {
            return CompositionTemplate.mock
        }

        return dtos.compactMap { dto in
            guard CompositionTemplateType.isSupportedTemplateID(dto.id) else {
                return nil
            }
            return CompositionTemplate(
                id: dto.id,
                name: dto.name,
                subtitle: dto.subtitle,
                philosophy: dto.philosophy,
                examples: dto.examples ?? []
            )
        }
    }()
}

extension CompositionTemplate {
    static let mock: [CompositionTemplate] = [
        CompositionTemplate(
            id: "rule_of_thirds",
            name: "Rule of Thirds",
            subtitle: "Balance and dynamic tension",
            philosophy: "Let the subject breathe within the frame.",
            examples: ["rule_of_thirds_01", "rule_of_thirds_02"]
        ),
        CompositionTemplate(
            id: "golden_spiral",
            name: "Golden Spiral",
            subtitle: "Natural visual flow",
            philosophy: "Guide attention along a quiet curve.",
            examples: ["golden_spiral_01", "golden_spiral_02"]
        ),
        CompositionTemplate(
            id: "center",
            name: "Center Composition",
            subtitle: "Intentional symmetry",
            philosophy: "Centering creates calm, confident focus.",
            examples: ["center_01", "center_02"]
        ),
        CompositionTemplate(
            id: "symmetry",
            name: "Symmetry",
            subtitle: "Reflections and balance",
            philosophy: "Mirror the scene for a refined order.",
            examples: ["symmetry_01", "symmetry_02"]
        ),
        CompositionTemplate(
            id: "leading_lines",
            name: "Leading Lines",
            subtitle: "Direct the viewer",
            philosophy: "Use lines to draw focus with intent.",
            examples: ["leading_lines_01", "leading_lines_02"]
        ),
        CompositionTemplate(
            id: "framing",
            name: "Framing",
            subtitle: "Layers and depth",
            philosophy: "Build a visual window for the subject.",
            examples: ["framing_01", "framing_02"]
        ),
        CompositionTemplate(
            id: "negative_space",
            name: "Negative Space",
            subtitle: "Minimal emphasis",
            philosophy: "Let emptiness amplify the subject.",
            examples: ["negative_space_01", "negative_space_02"]
        ),
        CompositionTemplate(
            id: "portrait_headroom",
            name: "Portrait Headroom",
            subtitle: "Eyes & headroom",
            philosophy: "Place eyes with intent and keep headroom clean.",
            examples: ["portrait_headroom_01", "portrait_headroom_02"]
        ),
        CompositionTemplate(
            id: "triangle",
            name: "Triangle Composition",
            subtitle: "Stable geometry",
            philosophy: "Triangles add balance and strong visual structure.",
            examples: ["triangle_01", "triangle_02"]
        )
    ]
}
