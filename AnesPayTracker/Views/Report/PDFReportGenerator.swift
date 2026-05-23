import Foundation
import UIKit
import PDFKit

// MARK: - PDF Report Generator

struct PDFReportGenerator {
    
    func generate(
        shifts: [Shift],
        startDate: Date,
        endDate: Date,
        employerFilter: String?,
        siteFilter: String?
    ) -> URL? {
        
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        
        let fileName = "AnesPay_Report_\(formatDate(startDate))_\(formatDate(endDate)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try renderer.writePDF(to: url) { context in
                var yOffset: CGFloat = margin
                
                context.beginPage()
                
                // MARK: Header
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: UIColor.label
                ]
                let title = NSAttributedString(string: "Pay Report", attributes: titleAttrs)
                title.draw(at: CGPoint(x: margin, y: yOffset))
                yOffset += 36
                
                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                
                let dateRange = "\(formatFullDate(startDate)) – \(formatFullDate(endDate))"
                let subtitle = NSAttributedString(string: dateRange, attributes: subtitleAttrs)
                subtitle.draw(at: CGPoint(x: margin, y: yOffset))
                yOffset += 24
                
                if let emp = employerFilter {
                    let empStr = NSAttributedString(string: "Employer: \(emp)", attributes: subtitleAttrs)
                    empStr.draw(at: CGPoint(x: margin, y: yOffset))
                    yOffset += 20
                }
                if let site = siteFilter {
                    let siteStr = NSAttributedString(string: "Site: \(site)", attributes: subtitleAttrs)
                    siteStr.draw(at: CGPoint(x: margin, y: yOffset))
                    yOffset += 20
                }
                
                yOffset += 16
                
                // Divider
                UIColor.separator.setStroke()
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: yOffset))
                line.addLine(to: CGPoint(x: pageWidth - margin, y: yOffset))
                line.lineWidth = 0.5
                line.stroke()
                yOffset += 12
                
                // MARK: Table Header
                let cols: [(String, CGFloat, NSTextAlignment)] = [
                    ("Date", 72, .left),
                    ("Site", 120, .left),
                    ("Duration", 60, .right),
                    ("Base", 72, .right),
                    ("Splash", 60, .right),
                    ("Streak", 60, .right),
                    ("Total", 72, .right)
                ]
                
                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                
                var xOffset = margin
                for (label, width, align) in cols {
                    let str = NSAttributedString(string: label.uppercased(), attributes: headerAttrs)
                    let rect = CGRect(x: xOffset, y: yOffset, width: width, height: 18)
                    str.draw(in: applyAlignment(rect, alignment: align))
                    xOffset += width
                }
                yOffset += 22
                
                // MARK: Table Rows
                let rowAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.label
                ]
                let rowBoldAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.label
                ]
                let accentAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor.systemBlue
                ]
                
                var totalBase: Decimal = 0
                var totalSplash: Decimal = 0
                var totalStreak: Decimal = 0
                var grandTotal: Decimal = 0
                
                for (i, shift) in shifts.enumerated() {
                    if yOffset > pageHeight - margin - 80 {
                        context.beginPage()
                        yOffset = margin
                    }
                    
                    // Alternate row background
                    if i % 2 == 0 {
                        let rowBg = UIBezierPath(rect: CGRect(x: margin - 4, y: yOffset - 2, width: contentWidth + 8, height: 22))
                        UIColor.systemGray6.setFill()
                        rowBg.fill()
                    }
                    
                    let rowValues: [(String, CGFloat, NSTextAlignment, [NSAttributedString.Key: Any])] = [
                        (formatShortDate(shift.date), 72, .left, rowAttrs),
                        ("\(shift.site?.name ?? "—")\(shift.hasStreakBonus ? " 🎯" : "")", 120, .left, rowBoldAttrs),
                        (durationText(shift), 60, .right, rowAttrs),
                        (shift.basePay.formatted(.currency(code: "USD")), 72, .right, rowAttrs),
                        (shift.splashAmount.map { $0 > 0 ? $0.formatted(.currency(code: "USD")) : "—" } ?? "—", 60, .right, rowAttrs),
                        ((shift.streakBonusAmount ?? 0) > 0 ? (shift.streakBonusAmount!.formatted(.currency(code: "USD"))) : "—", 60, .right, rowAttrs),
                        (shift.totalPay.formatted(.currency(code: "USD")), 72, .right, accentAttrs)
                    ]
                    
                    xOffset = margin
                    for (val, width, align, attrs) in rowValues {
                        let str = NSAttributedString(string: val, attributes: attrs)
                        let rect = CGRect(x: xOffset, y: yOffset, width: width, height: 18)
                        str.draw(in: applyAlignment(rect, alignment: align))
                        xOffset += width
                    }
                    yOffset += 22
                    
                    totalBase += shift.basePay
                    totalSplash += shift.splashAmount ?? 0
                    totalStreak += shift.streakBonusAmount ?? 0
                    grandTotal += shift.totalPay
                }
                
                // MARK: Totals Row
                yOffset += 8
                UIColor.separator.setStroke()
                let totLine = UIBezierPath()
                totLine.move(to: CGPoint(x: margin, y: yOffset))
                totLine.addLine(to: CGPoint(x: pageWidth - margin, y: yOffset))
                totLine.lineWidth = 0.5
                totLine.stroke()
                yOffset += 10
                
                let totAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.label
                ]
                let totAccentAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.systemBlue
                ]
                
                let totalsRow: [(String, CGFloat, NSTextAlignment, [NSAttributedString.Key: Any])] = [
                    ("TOTALS", 72, .left, totAttrs),
                    ("", 120, .left, totAttrs),
                    ("", 60, .right, totAttrs),
                    (totalBase.formatted(.currency(code: "USD")), 72, .right, totAttrs),
                    (totalSplash > 0 ? totalSplash.formatted(.currency(code: "USD")) : "—", 60, .right, totAttrs),
                    (totalStreak > 0 ? totalStreak.formatted(.currency(code: "USD")) : "—", 60, .right, totAttrs),
                    (grandTotal.formatted(.currency(code: "USD")), 72, .right, totAccentAttrs)
                ]
                
                xOffset = margin
                for (val, width, align, attrs) in totalsRow {
                    let str = NSAttributedString(string: val, attributes: attrs)
                    let rect = CGRect(x: xOffset, y: yOffset, width: width, height: 20)
                    str.draw(in: applyAlignment(rect, alignment: align))
                    xOffset += width
                }
                yOffset += 40
                
                // MARK: Footer
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.tertiaryLabel
                ]
                let footer = NSAttributedString(
                    string: "Generated by AnesPay on \(formatFullDate(Date()))",
                    attributes: footerAttrs
                )
                footer.draw(at: CGPoint(x: margin, y: pageHeight - margin))
            }
            
            return url
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func applyAlignment(_ rect: CGRect, alignment: NSTextAlignment) -> CGRect {
        rect
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yy"
        return f.string(from: date)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    private func durationText(_ shift: Shift) -> String {
        switch shift.payUnit {
        case .perDay: return shift.dayFraction?.label ?? "Full"
        case .perHour:
            let h = shift.hoursWorked ?? 0
            return "\(h.formatted())h"
        }
    }
}
