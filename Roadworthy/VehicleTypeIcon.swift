import SwiftUI

/// The vehicle type's icon: the custom pickup for Truck, an SF Symbol otherwise.
struct VehicleTypeIcon: View {
    let type: VehicleType
    var size: CGFloat = 20

    var body: some View {
        if let asset = type.customIconAsset {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.45, height: size * 0.81)
        } else {
            Image(systemName: type.iconName)
                .font(.system(size: size))
        }
    }
}
