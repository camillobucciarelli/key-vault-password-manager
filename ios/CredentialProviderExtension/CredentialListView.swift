import SwiftUI

struct CredentialListView: View {
  let credentials: [AutofillCredentialMetadata]
  let bestMatchId: String?
  let onSelect: (AutofillCredentialMetadata) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationView {
      Group {
        if credentials.isEmpty {
          EmptyCredentialsView()
        } else {
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
        }
      }
      .navigationTitle("Credentials")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}

private struct EmptyCredentialsView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "key.slash")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No matching credentials")
        .font(.headline)
      Text("Open KeyVault, unlock your vault, and publish the encrypted AutoFill cache before filling.")
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

private struct CredentialRowView: View {
  let credential: AutofillCredentialMetadata
  let isBestMatch: Bool

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color.accentColor.opacity(0.15))
        .frame(width: 40, height: 40)
        .overlay {
          Text(initial)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.accentColor)
        }

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(title)
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
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        if !credential.displayService.isEmpty {
          Text(credential.displayService)
            .font(.caption2)
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

  private var title: String {
    credential.title.isEmpty ? "Untitled" : credential.title
  }

  private var initial: String {
    String(title.prefix(1)).uppercased()
  }
}
