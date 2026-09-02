#if DEBUG
import Foundation
import SwiftData

/// Generates roughly two years of realistic-looking sample data for a
/// vehicle — fuel logs, maintenance, expenses, reminders, and trips — so
/// testing with realistic data volume (and taking good screenshots of the
/// Reports feature) doesn't require typing in hundreds of entries by hand.
///
/// This entire file is wrapped in #if DEBUG, so it's automatically excluded
/// from Release builds (TestFlight, App Store) — it doesn't exist in the
/// compiled app you submit, no manual cleanup required.
enum SampleDataGenerator {
    static func generate(for vehicle: Vehicle, context: ModelContext) {
        let calendar = Calendar.current
        let manufactureYearStart = calendar.date(from: DateComponents(year: vehicle.year, month: 1, day: 1)) ?? .now
        let twoYearsAgo = calendar.date(byAdding: .month, value: -24, to: .now) ?? .now
        let startDate = [twoYearsAgo, manufactureYearStart, vehicle.purchaseDate].max() ?? .now

        var currentMileage = max(0, vehicle.currentMileage - 24000)
        var currentDate = startDate

        // MARK: Fuel logs — every ~2 weeks, across the full 2-year span
        var checkpoints: [(date: Date, mileage: Int)] = []
        while currentDate < Date.now {
            currentMileage += Int.random(in: 280...420)
            let gallons = (Double.random(in: 10...15) * 10).rounded() / 10
            let price = (Double.random(in: 3.20...4.60) * 100).rounded() / 100

            let log = FuelLog(
                date: currentDate,
                mileage: currentMileage,
                gallons: gallons,
                pricePerGallon: price,
                isFullTank: true
            )
            log.vehicle = vehicle
            context.insert(log)

            checkpoints.append((currentDate, currentMileage))
            currentDate = calendar.date(byAdding: .day, value: Int.random(in: 12...17), to: currentDate) ?? currentDate
        }

        // MARK: Maintenance — 20 entries spread across the 2-year span
        let maintenanceTypes: [MaintenanceType] = [
            .oilChange, .oilChange, .oilChange, .oilChange, .oilChange,
            .tireRotation, .tireRotation, .tireRotation, .tireRotation,
            .brakes, .brakes,
            .battery,
            .fluids, .fluids,
            .inspection, .inspection,
            .airFilter, .airFilter,
            .tireReplacement,
            .registration
        ]
        for type in maintenanceTypes {
            guard let point = checkpoints.randomElement() else { continue }
            let cost: Double
            switch type {
            case .oilChange: cost = Double.random(in: 45...85)
            case .tireRotation: cost = Double.random(in: 20...40)
            case .brakes: cost = Double.random(in: 150...400)
            case .battery: cost = Double.random(in: 120...220)
            case .fluids: cost = Double.random(in: 60...120)
            case .inspection: cost = Double.random(in: 20...50)
            case .airFilter: cost = Double.random(in: 15...35)
            case .tireReplacement: cost = Double.random(in: 400...800)
            case .registration: cost = Double.random(in: 60...150)
            default: cost = Double.random(in: 30...100)
            }
            let record = MaintenanceRecord(
                type: type,
                date: point.date,
                mileage: point.mileage,
                cost: (cost * 100).rounded() / 100,
                notes: ""
            )
            record.vehicle = vehicle
            context.insert(record)
        }

        // MARK: Expenses — 30 entries spread across the 2-year span
        let expenseCategories: [ExpenseCategory] = [
            .insurance, .insurance, .insurance, .insurance, .insurance, .insurance, .insurance, .insurance,
            .parking, .parking, .parking, .parking, .parking,
            .tolls, .tolls, .tolls, .tolls, .tolls,
            .carWash, .carWash, .carWash, .carWash, .carWash,
            .accessories, .accessories, .accessories, .accessories,
            .fines, .fines, .fines
        ]
        for category in expenseCategories {
            let daySpan = calendar.dateComponents([.day], from: startDate, to: .now).day ?? 0
            let randomDate = calendar.date(byAdding: .day, value: Int.random(in: 0...max(1, daySpan)), to: startDate) ?? startDate
            let cost: Double
            switch category {
            case .insurance: cost = Double.random(in: 90...160)
            case .parking: cost = Double.random(in: 5...25)
            case .tolls: cost = Double.random(in: 2...15)
            case .carWash: cost = Double.random(in: 10...30)
            case .accessories: cost = Double.random(in: 15...80)
            case .fines: cost = Double.random(in: 50...200)
            default: cost = Double.random(in: 10...50)
            }
            let expense = ExpenseRecord(
                category: category,
                date: min(randomDate, .now),
                amount: (cost * 100).rounded() / 100,
                notes: ""
            )
            expense.vehicle = vehicle
            context.insert(expense)
        }

        // MARK: Reminders — one overdue, one upcoming, one on track
        let overdueReminder = MaintenanceReminder(
            title: "Registration Renewal",
            type: .registration,
            repeatByDate: true,
            intervalMonths: 12,
            baselineDate: calendar.date(byAdding: .month, value: -13, to: .now) ?? .now
        )
        overdueReminder.vehicle = vehicle
        context.insert(overdueReminder)

        let upcomingReminder = MaintenanceReminder(
            title: "Oil Change",
            type: .oilChange,
            repeatByMileage: true,
            intervalMiles: 5000,
            baselineMileage: max(0, currentMileage - 4700)
        )
        upcomingReminder.vehicle = vehicle
        context.insert(upcomingReminder)

        let onTrackReminder = MaintenanceReminder(
            title: "Tire Rotation",
            type: .tireRotation,
            repeatByMileage: true,
            intervalMiles: 6000,
            baselineMileage: currentMileage
        )
        onTrackReminder.vehicle = vehicle
        context.insert(onTrackReminder)

        // MARK: Trips — business mileage, using nearby real mileage checkpoints
        let businessPurposes = ["Client meeting", "Parts pickup", "Job site visit", "Supply run", "Delivery"]
        for _ in 0..<15 {
            guard let point = checkpoints.randomElement() else { continue }
            let miles = Int.random(in: 8...60)
            let trip = TripLog(
                date: point.date,
                startMileage: point.mileage,
                endMileage: point.mileage + miles,
                purpose: .business,
                businessPurposeNote: businessPurposes.randomElement() ?? "Business trip"
            )
            trip.vehicle = vehicle
            context.insert(trip)
        }

        // Keep the vehicle's current mileage in sync with the newest fuel log.
        if currentMileage > vehicle.currentMileage {
            vehicle.currentMileage = currentMileage
        }
    }
}
#endif
