//
//  ThemesPanel.swift
//  winston
//
//  Created by Igor Marcossi on 08/09/23.
//

import SwiftUI
import UniformTypeIdentifiers
import Defaults
import Zip

struct ThemesPanel: View {
  @Default(.themesPresets) private var themesPresets
  @State private var isUnzipping = false
  var body: some View {
    List {
      
      ForEach(themesPresets) { theme in
        Group {
          if theme.id == "default" {
            ThemeNavLink(theme: theme)
              .deleteDisabled(true)
          } else {
            NavigationLink(value: theme) {
              ThemeNavLink(theme: theme)
            }
          }
        }
      }
      .onDelete { index in
        withAnimation { themesPresets.remove(atOffsets: index) }
      }
      
      Section {
        Button("Unzip Theme") {
          isUnzipping = true
        }
        .fileImporter(isPresented: $isUnzipping,
                      allowedContentTypes: [UTType.zip],
                      allowsMultipleSelection: false) { res in
          do {
            switch res {
            case .success(let file):
              unzipTheme(at: file[0])
            case .failure(let error):
              print(error.localizedDescription)
            }
          } catch {
            print("Failed to import file with error: \(error.localizedDescription)")
          }
        }
      }
      
    }
    .overlay(
      themesPresets.count > 1
      ? nil
      : VStack(spacing: 0) {
        Text("Start duplicating the")
        HStack(spacing: 4) {
          Text("default theme by tapping")
          Image(systemName: "plus")
        }
      }
        .compositingGroup()
        .opacity(0.25)
    )
    .navigationTitle("Themes")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      EditButton()
      Button {
        withAnimation { themesPresets.append(defaultTheme.duplicate()) }
      } label: {
        Image(systemName: "plus")
      }
    }
    .navigationDestination(for: WinstonTheme.self) { theme in
      ThemeEditPanel(themeEditedInstance: ThemeEditedInstance(theme))
    }
  }
  
  func unzipTheme(at fileURL: URL) {
    do {
      let gotAccess = fileURL.startAccessingSecurityScopedResource()
      if !gotAccess { return }
      
      let unzipDirectory = try Zip.quickUnzipFile(fileURL)
      fileURL.stopAccessingSecurityScopedResource()
      let fileManager = FileManager.default
      let themeJsonURL = unzipDirectory.appendingPathComponent("theme.json")
      let themeData = try Data(contentsOf: themeJsonURL)
      let theme = try JSONDecoder().decode(WinstonTheme.self, from: themeData)
      
      let urls = try fileManager.contentsOfDirectory(at: unzipDirectory, includingPropertiesForKeys: nil)
      let destinationURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
      for url in urls {
        if url.lastPathComponent != "theme.json" {
          let destinationFileURL = destinationURL.appendingPathComponent(url.lastPathComponent)
          try? fileManager.removeItem(at: destinationFileURL)
          try fileManager.moveItem(at: url, to: destinationFileURL)
        }
      }
      
      DispatchQueue.main.async {
        themesPresets.append(theme)
      }
    } catch {
      print("Failed to unzip file with error: \(error.localizedDescription)")
    }
  }
}

struct ThemeNavLink: View {
  @Default(.selectedThemeID) private var selectedThemeID
  @Default(.themesPresets) private var themesPresets
  @State private var restartAlert = false
  
  @Environment(\.useTheme) private var selectedTheme
  @State private var isMoving = false
  @State private var zipUrl: URL? = nil
  var theme: WinstonTheme
  var body: some View {
    let isDefault = theme.id == "default"
    HStack(spacing: 8) {
      Group {
        if isDefault {
          Image("winstonFlat")
            .resizable()
            .scaledToFit()
            .frame(height: 36)
        } else {
          Image(systemName: theme.metadata.icon)
            .fontSize(24)
            .foregroundColor(.white)
        }
      }
      .frame(width: 52, height: 52)
      .background(RR(16, theme.metadata.color.color()))
      VStack(alignment: .leading, spacing: 0) {
        Text(theme.metadata.name)
          .fontSize(16, .semibold)
          .fixedSize(horizontal: true, vertical: false)
        Text("Created by \(theme.metadata.author)")
          .fontSize(14, .medium)
          .opacity(0.75)
          .fixedSize(horizontal: true, vertical: false)
      }
      
      Spacer()
      
      Toggle("", isOn: Binding(get: { selectedTheme == theme  }, set: { _ in
        if themesPresets.first(where: { $0.id == selectedThemeID })?.general != theme.general { restartAlert = true  }
        selectedThemeID = theme.id
      }))
    }
    .contextMenu {
      Button {
        withAnimation { themesPresets.append(theme.duplicate()) }
      } label: {
        Label("Duplicate", systemImage: "plus.square.on.square")
      }
      Button {
        var imgNames: [String] = []
        if case .img(let schemesStr) = theme.postLinks.bg {
          imgNames.append(schemesStr.light)
          imgNames.append(schemesStr.dark)
        }
        if case .img(let schemesStr) = theme.posts.bg {
          imgNames.append(schemesStr.light)
          imgNames.append(schemesStr.dark)
        }
        if case .img(let schemesStr) = theme.lists.bg {
          imgNames.append(schemesStr.light)
          imgNames.append(schemesStr.dark)
        }
        createZipFile(with: imgNames, theme: theme.duplicate()) { url in
          self.zipUrl = url
          self.isMoving = true
        }
      } label: {
        Label("Export", systemImage: "doc.zipper")
      }
    }
    .fileMover(isPresented: $isMoving, file: zipUrl, onCompletion: { result in
      switch result {
      case .success(let url):
        print("Successfully moved the file to \(url)")
      case .failure(let error):
        print("Failed to move the file with error \(error)")
      }
    })
    .alert("Restart required", isPresented: $restartAlert) {
      Button("Gotcha!", role: .cancel) {
        restartAlert = false
      }
    } message: {
      Text("This theme changes a few settings that requires an app restart to take effect.")
    }
  }
  
  func createZipFile(with imgNames: [String], theme: WinstonTheme, completion: @escaping(_ url: URL?) -> Void) {
    do {
      let zipURL = try createZip(images: imgNames, theme: theme)
      completion(zipURL)
    } catch {
      print("Failed to create zip file with error \(error.localizedDescription)")
      completion(nil)
    }
  }
}