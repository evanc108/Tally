import SwiftUI
import PhotosUI

struct CircleNameView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    @State private var placeholderIndex = 0

    private let placeholders = ["Ski Trip", "Roommates", "Date Night", "Road Trip", "Game Day"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Title
                    Text("Name your circle")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, TallySpacing.sm)

                    // Photo upload — centered
                    PhotosPicker(selection: Binding(
                        get: { state.photoPickerItem },
                        set: { item in
                            state.photoPickerItem = item
                            loadPhoto(from: item)
                        }
                    ), matching: .images) {
                        if let photo = state.photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 132, height: 132)
                                .clipShape(Circle())
                                .overlay(alignment: .bottomTrailing) { editBadge }
                        } else {
                            ZStack {
                                Circle()
                                    .fill(TallyColors.bgSecondary)
                                    .frame(width: 132, height: 132)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(TallyColors.textSecondary)
                            }
                            .overlay(alignment: .bottomTrailing) { plusBadge }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, TallySpacing.xxl)

                    Text(state.photo == nil ? "Add a photo" : "Tap to change")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // Name input
                    ZStack(alignment: .leading) {
                        if state.circleName.isEmpty {
                            Text(placeholders[placeholderIndex])
                                .font(TallyFont.body)
                                .foregroundStyle(TallyColors.textSecondary.opacity(0.5))
                                .animation(.easeInOut(duration: 0.3), value: placeholderIndex)
                        }
                        TextField("", text: $state.circleName)
                            .font(TallyFont.body)
                            .foregroundStyle(TallyColors.textPrimary)
                    }
                    .frame(height: TallySpacing.inputHeight)
                    .padding(.horizontal, TallySpacing.lg)
                    .background(TallyColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardInnerRadius))
                    .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
            }

            // Continue button
            Button("Continue", action: onContinue)
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(!state.isNameValid)
                .opacity(state.isNameValid ? 1 : 0.5)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear { startPlaceholderRotation() }
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(TallyColors.accent)
            .clipShape(Circle())
            .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 2))
    }

    private var editBadge: some View {
        Image(systemName: "pencil")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(TallyColors.accent)
            .clipShape(Circle())
            .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 2))
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                state.photo = image
            }
        }
    }

    private func startPlaceholderRotation() {
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation { placeholderIndex = (placeholderIndex + 1) % placeholders.count }
        }
    }
}
