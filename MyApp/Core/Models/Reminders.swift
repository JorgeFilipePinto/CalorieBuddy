import Foundation

/// A time window of a reminder, in minutes since midnight (Lisbon/local time of the device).
struct ReminderWindow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startMinute: Int
    /// Last minute at which the reminder may still fire; ignored when `repeatMinutes` is nil.
    var endMinute: Int
    /// Fires again every N minutes inside the window until it is confirmed (nil = once, at the start).
    var repeatMinutes: Int?

    /// The minutes of the day at which this window fires.
    var fireMinutes: [Int] {
        guard let step = repeatMinutes, step > 0, endMinute > startMinute else { return [startMinute] }
        return Array(stride(from: startMinute, through: endMinute, by: step))
    }

    static func label(forMinute minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    var summary: String {
        let range = repeatMinutes == nil || endMinute <= startMinute
            ? Self.label(forMinute: startMinute)
            : "\(Self.label(forMinute: startMinute))–\(Self.label(forMinute: endMinute))"
        guard let step = repeatMinutes, endMinute > startMinute else { return range }
        return "\(range), de \(step) em \(step) min"
    }
}

/// A free reminder ("Tomar creatina", "Beber shake"): not linked to any food or supplement. It fires
/// in one or more time windows on the chosen weekdays, and asks whether it was taken; confirming
/// stops that window's remaining notifications for the day.
struct Reminder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var note: String? = nil
    var isEnabled: Bool = true
    /// `Calendar` weekdays (1 = Sunday … 7 = Saturday) the reminder repeats on.
    var weekdays: [Int] = Array(1...7)
    var windows: [ReminderWindow] = []
    /// Windows already confirmed, as `"yyyy-MM-dd|<window id>"`; old days are dropped.
    var doneKeys: [String] = []

    init(id: UUID = UUID(), title: String, note: String? = nil, isEnabled: Bool = true,
         weekdays: [Int] = Array(1...7), windows: [ReminderWindow] = [], doneKeys: [String] = []) {
        self.id = id
        self.title = title
        self.note = note
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.windows = windows
        self.doneKeys = doneKeys
    }

    private enum CodingKeys: String, CodingKey { case id, title, note, isEnabled, weekdays, windows, doneKeys }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? Array(1...7)
        windows = try c.decodeIfPresent([ReminderWindow].self, forKey: .windows) ?? []
        doneKeys = try c.decodeIfPresent([String].self, forKey: .doneKeys) ?? []
    }

    static func doneKey(day: String, window: UUID) -> String { "\(day)|\(window.uuidString)" }

    func isDone(day: String, window: UUID) -> Bool { doneKeys.contains(Self.doneKey(day: day, window: window)) }

    static let weekdayLetters = ["D", "S", "T", "Q", "Q", "S", "S"]
    static let weekdayNames = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]

    var weekdaySummary: String {
        let days = Set(weekdays)
        if days.count == 7 { return "Todos os dias" }
        if days == [2, 3, 4, 5, 6] { return "Dias úteis" }
        if days == [1, 7] { return "Fins de semana" }
        return (1...7).filter(days.contains).map { String(Self.weekdayNames[$0 - 1].prefix(3)) }.joined(separator: ", ")
    }
}
