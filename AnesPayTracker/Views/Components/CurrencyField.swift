import SwiftUI

// MARK: - Currency Field

struct CurrencyField: View {
    @Binding var value: Decimal
    let placeholder: String
    
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Text("$")
                .foregroundStyle(.secondary)
                .font(.body)
            
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    // Strip non-numeric except period
                    let filtered = newVal.filter { $0.isNumber || $0 == "." }
                    if filtered != newVal { text = filtered }
                    value = Decimal(string: filtered) ?? 0
                }
                .onChange(of: isFocused) { _, focused in
                    if focused && (value == 0 || text == "0") {
                        text = ""
                    } else if !focused {
                        if value == 0 { text = "" }
                    }
                }
        }
        .onAppear {
            if value > 0 {
                text = NSDecimalNumber(decimal: value).stringValue
            }
        }
    }
}
