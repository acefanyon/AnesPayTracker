import Foundation
import UIKit

// MARK: - Invoice Document

/// Everything needed to print an invoice. Built from a saved `Invoice`, or
/// from the editor for a preview before saving.
struct InvoiceDocument {
    let number: String
    let issuedOn: Date
    let dueOn: Date?
    let periodStart: Date
    let periodEnd: Date
    let notes: String?
    let snapshot: InvoiceSnapshot

    init(number: String, issuedOn: Date, dueOn: Date?, periodStart: Date, periodEnd: Date, notes: String?, snapshot: InvoiceSnapshot) {
        self.number = number
        self.issuedOn = issuedOn
        self.dueOn = dueOn
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.notes = notes
        self.snapshot = snapshot
    }

    init?(invoice: Invoice) {
        guard let snapshot = invoice.snapshot else { return nil }
        self.init(
            number: invoice.number,
            issuedOn: invoice.issuedOn,
            dueOn: invoice.dueOn,
            periodStart: invoice.periodStart,
            periodEnd: invoice.periodEnd,
            notes: invoice.notes,
            snapshot: snapshot
        )
    }
}

// MARK: - Invoice PDF Generator

struct InvoicePDFGenerator {

    func generate(_ document: InvoiceDocument) -> URL? {
        let pageBounds = CGRect(x: 0, y: 0, width: InvoicePDFCanvas.pageWidth, height: InvoicePDFCanvas.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let safeNumber = document.number.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Invoice-\(safeNumber).pdf")

        do {
            try renderer.writePDF(to: url) { context in
                let canvas = InvoicePDFCanvas(context: context, footer: "Invoice \(document.number)")
                canvas.beginPage()
                drawHeader(document, on: canvas)
                drawParties(document, on: canvas)
                drawTableHeader(on: canvas)
                for day in document.snapshot.days {
                    drawDay(day, on: canvas)
                }
                drawTotal(document, on: canvas)
                drawNotes(document, on: canvas)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: Sections

    private func drawHeader(_ document: InvoiceDocument, on canvas: InvoicePDFCanvas) {
        let snapshot = document.snapshot
        canvas.fill(CGRect(x: canvas.left, y: canvas.y, width: canvas.width, height: 4), color: InvoicePDFCanvas.accent)
        canvas.y += 16

        canvas.text(snapshot.senderName, font: .systemFont(ofSize: 20, weight: .bold), color: InvoicePDFCanvas.accent, lineHeight: 26)
        let contactLines = InvoiceMath.addressLines(snapshot.senderAddress)
            + [snapshot.senderPhone, snapshot.senderEmail].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for line in contactLines {
            canvas.text(line, font: .systemFont(ofSize: 10), color: .darkGray, lineHeight: 14)
        }

        canvas.y += 18
        canvas.text("Invoice", font: .systemFont(ofSize: 26, weight: .bold), lineHeight: 36)
        canvas.y += 6
    }

    private func drawParties(_ document: InvoiceDocument, on canvas: InvoicePDFCanvas) {
        let snapshot = document.snapshot
        let top = canvas.y
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        let valueFont = UIFont.systemFont(ofSize: 10)

        // Column 1: who is billed.
        var y1 = top
        canvas.draw("Invoice for", x: canvas.left, y: y1, width: 200, font: labelFont)
        y1 += 15
        for line in [snapshot.billToName] + InvoiceMath.addressLines(snapshot.billToAddress) {
            canvas.draw(line, x: canvas.left, y: y1, width: 200, font: valueFont, color: .darkGray)
            y1 += 14
        }

        // Column 2: who is paid. Each day names its own site below.
        var y2 = top
        canvas.draw("Payable to", x: canvas.left + 215, y: y2, width: 150, font: labelFont)
        y2 += 15
        canvas.draw(snapshot.senderName, x: canvas.left + 215, y: y2, width: 150, font: valueFont, color: .darkGray)
        y2 += 14

        // Column 3: invoice facts.
        var y3 = top
        var facts: [(String, String)] = [
            ("Invoice #", document.number),
            ("Date", Self.shortDate.string(from: document.issuedOn)),
        ]
        if let dueOn = document.dueOn {
            facts.append(("Due date", Self.shortDate.string(from: dueOn)))
        }
        facts.append(("Service dates", "\(Self.shortDate.string(from: document.periodStart)) – \(Self.shortDate.string(from: document.periodEnd))"))
        for (label, value) in facts {
            canvas.draw(label, x: canvas.left + 380, y: y3, width: 136, font: labelFont)
            y3 += 14
            canvas.draw(value, x: canvas.left + 380, y: y3, width: 136, font: valueFont, color: .darkGray)
            y3 += 18
        }

        canvas.y = max(y1, y2, y3) + 14
    }

    private func drawTableHeader(on canvas: InvoicePDFCanvas) {
        canvas.fill(CGRect(x: canvas.left, y: canvas.y, width: canvas.width, height: 20), color: InvoicePDFCanvas.band)
        let font = UIFont.systemFont(ofSize: 10, weight: .bold)
        canvas.draw("Description", x: canvas.left + 6, y: canvas.y + 4, width: 250, font: font, color: InvoicePDFCanvas.accent)
        canvas.draw("Time", x: canvas.left + 220, y: canvas.y + 4, width: 190, font: font, color: InvoicePDFCanvas.accent, alignment: .right)
        canvas.draw("Amount", x: canvas.amountX, y: canvas.y + 4, width: canvas.amountWidth - 6, font: font, color: InvoicePDFCanvas.accent, alignment: .right)
        canvas.y += 26
    }

    private func drawDay(_ day: InvoiceDay, on canvas: InvoicePDFCanvas) {
        // Keep the date with at least its first rows.
        canvas.ensureSpace(64)

        canvas.draw(Self.longDate.string(from: day.date), x: canvas.left + 6, y: canvas.y, width: 230, font: .systemFont(ofSize: 11, weight: .bold))
        canvas.draw(day.siteName, x: canvas.left + 240, y: canvas.y + 1, width: canvas.width - 246, font: .systemFont(ofSize: 10, weight: .semibold), color: .darkGray, alignment: .right)
        canvas.y += 18

        let rowFont = UIFont.systemFont(ofSize: 10)
        for line in day.caseLines {
            canvas.ensureSpace(16)
            let time = "\(Self.time.string(from: line.startAt)) – \(Self.time.string(from: line.endAt))   \(CaseTimeCalculator.durationLabel(minutes: line.minutes))"
            canvas.draw(line.label, x: canvas.left + 14, y: canvas.y, width: 210, font: rowFont, color: .darkGray)
            canvas.draw(time, x: canvas.left + 220, y: canvas.y, width: 190, font: rowFont, color: .darkGray, alignment: .right)
            canvas.y += 15
        }
        if !day.caseLines.isEmpty { canvas.y += 3 }

        for charge in day.charges {
            canvas.ensureSpace(16)
            let description = charge.detail.isEmpty ? charge.label : "\(charge.label): \(charge.detail)"
            canvas.draw(description, x: canvas.left + 14, y: canvas.y, width: 396, font: rowFont)
            canvas.draw(Self.money(charge.amountCents), x: canvas.amountX, y: canvas.y, width: canvas.amountWidth - 6, font: rowFont, alignment: .right)
            canvas.y += 15
        }

        canvas.ensureSpace(24)
        canvas.rule(from: canvas.left + 300, to: canvas.right, y: canvas.y + 2)
        canvas.y += 6
        let totalFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        canvas.draw("Day total", x: canvas.left + 220, y: canvas.y, width: 190, font: totalFont, alignment: .right)
        canvas.draw(Self.money(day.totalCents), x: canvas.amountX, y: canvas.y, width: canvas.amountWidth - 6, font: totalFont, alignment: .right)
        canvas.y += 24
    }

    private func drawTotal(_ document: InvoiceDocument, on canvas: InvoicePDFCanvas) {
        canvas.ensureSpace(56)
        canvas.rule(from: canvas.left, to: canvas.right, y: canvas.y)
        canvas.y += 12
        canvas.draw("Total due", x: canvas.left + 200, y: canvas.y + 4, width: 180, font: .systemFont(ofSize: 12, weight: .bold), alignment: .right)
        canvas.draw(
            Self.money(document.snapshot.totalCents),
            x: canvas.left + 386, y: canvas.y, width: canvas.width - 392,
            font: .systemFont(ofSize: 18, weight: .bold), color: InvoicePDFCanvas.accent, alignment: .right, lineHeight: 24
        )
        canvas.y += 36
    }

    private func drawNotes(_ document: InvoiceDocument, on canvas: InvoicePDFCanvas) {
        guard let notes = document.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return }
        canvas.ensureSpace(48)
        canvas.text("Notes", font: .systemFont(ofSize: 10, weight: .bold), lineHeight: 15)
        for line in InvoiceMath.addressLines(notes) {
            canvas.ensureSpace(14)
            canvas.text(line, font: .systemFont(ofSize: 10), color: .darkGray, lineHeight: 14)
        }
    }

    // MARK: Formatting

    private static func money(_ cents: Int) -> String {
        InvoiceMath.dollars(cents: cents).formatted(.currency(code: "USD"))
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    private static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

// MARK: - Canvas

/// A page cursor for drawing rows top to bottom, starting a new page when one fills.
private final class InvoicePDFCanvas {
    static let pageWidth: CGFloat = 612   // US Letter
    static let pageHeight: CGFloat = 792
    static let margin: CGFloat = 48
    static let accent = UIColor(red: 0.07, green: 0.13, blue: 0.55, alpha: 1)
    static let band = UIColor(white: 0.94, alpha: 1)

    let context: UIGraphicsPDFRendererContext
    let footer: String
    var y: CGFloat = 0
    private var pageNumber = 0

    var left: CGFloat { Self.margin }
    var right: CGFloat { Self.pageWidth - Self.margin }
    var width: CGFloat { Self.pageWidth - Self.margin * 2 }
    var amountX: CGFloat { right - 100 }
    var amountWidth: CGFloat { 100 }

    init(context: UIGraphicsPDFRendererContext, footer: String) {
        self.context = context
        self.footer = footer
    }

    func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = Self.margin
        draw(
            "\(footer) · Page \(pageNumber)",
            x: left, y: Self.pageHeight - 34, width: width,
            font: .systemFont(ofSize: 8), color: .gray, alignment: .center
        )
    }

    func ensureSpace(_ height: CGFloat) {
        if y + height > Self.pageHeight - Self.margin - 12 {
            beginPage()
        }
    }

    /// One line of text at an exact position; long text is cut with an ellipsis.
    func draw(
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        lineHeight: CGFloat? = nil
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let rect = CGRect(x: x, y: y, width: width, height: lineHeight ?? (font.lineHeight + 2))
        (string as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// One full-width line at the cursor, then moves the cursor down.
    func text(_ string: String, font: UIFont, color: UIColor = .black, lineHeight: CGFloat) {
        draw(string, x: left, y: y, width: width, font: font, color: color, lineHeight: lineHeight)
        y += lineHeight
    }

    func fill(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIRectFill(rect)
    }

    func rule(from startX: CGFloat, to endX: CGFloat, y: CGFloat) {
        UIColor(white: 0.75, alpha: 1).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        path.lineWidth = 0.5
        path.stroke()
    }
}
