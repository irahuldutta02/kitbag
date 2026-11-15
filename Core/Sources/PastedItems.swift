import AppKit

/// Text, links and images pasted into the shelf are kept as small files in a cache folder. When they
/// are sent to another app they should arrive as what they really are: a link as a link, text as text.
public enum PastedItems {
  public static var root: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/Pasted", isDirectory: true)
  }

  public static func isPasted(_ url: URL) -> Bool {
    url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
  }

  /// What to put on the pasteboard for `url`: the web link inside a pasted link file, otherwise the file.
  /// A link is one item with both its URL and plain-text forms; Blip's Service only reacts to that
  /// (a bare URL object or bare text is ignored, so its window never opens). Pasted text stays a
  /// `.txt` file for the same reason.
  public static func payload(for url: URL) -> NSPasteboardWriting {
    guard isPasted(url), url.pathExtension.lowercased() == "webloc",
      let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let link = plist["URL"] as? String
    else { return url as NSURL }
    let item = NSPasteboardItem()
    item.setString(link, forType: .URL)
    item.setString(link, forType: .string)
    return item
  }
}
