//
//  ConfirmDestructiveAction.swift
//  EclipsePlexClient
//

import SwiftUI

struct ConfirmDestructiveAction: ViewModifier {
    let title: String
    let message: String
    let confirmLabel: String
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button(confirmLabel, role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func confirmDestructive(
        title: String,
        message: String,
        confirmLabel: String = "Delete",
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            ConfirmDestructiveAction(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                isPresented: isPresented,
                onConfirm: onConfirm
            )
        )
    }
}
