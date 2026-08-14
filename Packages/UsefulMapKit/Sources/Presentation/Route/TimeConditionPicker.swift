import Domain
import SwiftUI

/// 「いま / 出発時刻 / 到着時刻」と日時の指定。
///
/// 検索前の条件入力と、経路を開いたあとの変更の両方で使う。
struct TimeConditionPicker: View {
    let preference: TimePreference
    let date: Date?
    let now: () -> Date
    let onChange: (TimePreference, Date?) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.tint)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.timeCondition)
            .accessibilityValue(summary)

            if isExpanded {
                Picker(L10n.string("editor.timeCondition"), selection: Binding(
                    get: { preference },
                    set: { onChange($0, $0.requiresDate ? (date ?? now()) : nil) }
                )) {
                    ForEach(TimePreference.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(A11y.timePreferencePicker)

                if preference.requiresDate {
                    DatePicker(L10n.string("editor.dateTime"),
                               selection: Binding(
                                get: { date ?? now() },
                                set: { onChange(preference, $0) }
                               ))
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier(A11y.datePicker)
                }
            }
        }
    }

    /// 「いま出発」「9/1 10:32 に出発」「9/1 11:00 に到着」
    private var summary: String {
        guard preference.requiresDate, let date else {
            return L10n.string("time.departNow")
        }
        let stamp = "\(Formatters.historyTimestamp(date, now: now())) "
            .trimmingCharacters(in: .whitespaces)
        return preference == .arriveBy
            ? L10n.string("time.arriveAt", stamp)
            : L10n.string("time.departAt", stamp)
    }
}
