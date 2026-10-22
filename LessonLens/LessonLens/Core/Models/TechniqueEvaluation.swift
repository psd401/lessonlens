import Foundation
import SwiftData
import SwiftUI

/// Evaluation of a specific teaching technique within an analysis
@Model
final class TechniqueEvaluation {
    // MARK: - Properties
    @Attribute(.unique) var id: UUID
    var techniqueId: String  // References Technique.id
    var techniqueName: String  // Denormalized for display
    var rating: Int?  // 1-5 scale, nil if not observed
    var feedback: String
    var wasObserved: Bool

    // MARK: - JSON-stored arrays
    var evidenceData: Data?
    var suggestionsData: Data?

    // MARK: - Relationships
    var analysis: Analysis?

    // MARK: - Computed Properties
    var evidence: [String] {
        get {
            guard let data = evidenceData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            evidenceData = try? JSONEncoder().encode(newValue)
        }
    }

    var suggestions: [String] {
        get {
            guard let data = suggestionsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            suggestionsData = try? JSONEncoder().encode(newValue)
        }
    }

    var ratingLevel: RatingLevel? {
        guard let rating = rating else { return nil }
        return RatingLevel(rawValue: rating)
    }

    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        techniqueId: String,
        techniqueName: String,
        rating: Int? = nil,
        feedback: String,
        wasObserved: Bool = true,
        evidence: [String] = [],
        suggestions: [String] = []
    ) {
        self.id = id
        self.techniqueId = techniqueId
        self.techniqueName = techniqueName
        self.rating = rating
        self.feedback = feedback
        self.wasObserved = wasObserved
        self.evidenceData = try? JSONEncoder().encode(evidence)
        self.suggestionsData = try? JSONEncoder().encode(suggestions)
    }
}

// MARK: - Rating Level

/// How fully a technique was carried out when it came up in the lesson, not
/// how often. A technique that didn't come up has no rating ("Not observed").
/// Must match RATING_SCALE in shared/prompts/templates/components.ts.
enum RatingLevel: Int, CaseIterable {
    case emerging = 1
    case developing = 2
    case established = 3
    case refining = 4
    case extending = 5

    var displayText: String {
        switch self {
        case .emerging: return "Emerging"
        case .developing: return "Developing"
        case .established: return "Established"
        case .refining: return "Refining"
        case .extending: return "Extending"
        }
    }

    var color: String {
        switch self {
        case .emerging: return "red"
        case .developing: return "orange"
        case .established: return "driftwood"
        case .refining: return "meadow"
        case .extending: return "whulge"
        }
    }

    var description: String {
        switch self {
        case .emerging:
            return "Attempted, with few look-fors present."
        case .developing:
            return "Used with some look-fors present; key elements missing, or uneven when it came up more than once."
        case .established:
            return "Used as intended, with most look-fors present."
        case .refining:
            return "Used as intended, with attention to finer points such as timing, wording and follow-through."
        case .extending:
            return "Used as intended and taken further: adapted to individual students, or students took it up themselves with little prompting."
        }
    }

    var swiftUIColor: Color {
        PSDTheme.ratingColor(self.rawValue)
    }
}
