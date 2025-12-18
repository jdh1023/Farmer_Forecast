import SwiftUI
import MapKit
import CoreLocation

// MARK: - 3. Map Picker View (Updated for iOS 17+)
struct LocationPickerView: View {
    @Environment(\.dismiss) var dismiss
    
    // Callbacks
    var onConfirm: (Double, Double) -> Void
    
    // Map State
    @State private var cameraPosition: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D
    
    init(lat: Double, lon: Double, onConfirm: @escaping (Double, Double) -> Void) {
        self.onConfirm = onConfirm
        
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        // Initialize state
        _selectedCoordinate = State(initialValue: center)
        
        // Set initial region
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        _cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // Show a marker where the user is looking
                Annotation("Location", coordinate: selectedCoordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.title)
                }
            }
            // Update the coordinate as the user moves the map
            .onMapCameraChange(frequency: .continuous) { context in
                selectedCoordinate = context.region.center
            }
            .ignoresSafeArea()
            
            // Crosshair overlay
            Image(systemName: "plus")
                .font(.largeTitle)
                .foregroundColor(.black.opacity(0.5))
            
            VStack {
                Spacer()
                Button(action: {
                    // Force a tiny vibration feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    // Send the coordinates back
                    onConfirm(selectedCoordinate.latitude, selectedCoordinate.longitude)
                    dismiss()
                }) {
                    Text("Set Location Here")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}
