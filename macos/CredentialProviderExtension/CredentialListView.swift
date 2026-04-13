import AuthenticationServices
import SwiftUI

struct CredentialListView: View {
  let credentials: [SharedAutofillCredential]
  let bestMatchId: String?
  let onSelect: (SharedAutofillCredential) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationView {
      List(credentials, id: \.id) { credential in
        Button {
          onSelect(credential)
        } label: {
          CredentialRowView(
            credential: credential,
            isBestMatch: credential.id == bestMatchId
          )
        }
        .buttonStyle(.plain)
      }
      .listStyle(.plain)
      .navigationTitle("Credentials")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}

private struct CredentialRowView: View {
  let credential: SharedAutofillCredential
  let isBestMatch: Bool

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color.accentColor.opacity(0.15))
        .frame(width: 40, height: 40)
        .overlay {
          Text(credential.title.prefix(1).uppercased())
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.accentColor)
        }

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(credential.title.isEmpty ? "Unnamed" : credential.title)
            .font(.body)
            .foregroundColor(.primary)
            .lineLimit(1)
          if isBestMatch {
            Text("Best match")
              .font(.caption2)
              .fontWeight(.medium)
              .foregroundColor(.accentColor)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.12))
              .clipShape(Capsule())
          }
        }
        if !credential.username.isEmpty {
          Text(credential.username)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary.opacity(0.5))
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}
