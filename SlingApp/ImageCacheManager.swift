import SwiftUI
import Foundation

// MARK: - Image Cache Manager
class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Configure cache limits
        cache.countLimit = 100 // Maximum 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit
        
        // Set up disk cache directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("ImageCache")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let cacheKey = NSString(string: urlString)
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }
        
        // Check disk cache
        let diskCacheURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        if let diskImage = UIImage(contentsOfFile: diskCacheURL.path) {
            // Store in memory cache
            cache.setObject(diskImage, forKey: cacheKey)
            completion(diskImage)
            return
        }
        
        // Download image
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Store in memory cache
            self?.cache.setObject(image, forKey: cacheKey)
            
            // Store in disk cache
            try? data.write(to: diskCacheURL)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    func preloadImages(urls: [String]) {
        for urlString in urls {
            loadImage(from: urlString) { _ in
                // Preload completed
            }
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Optimized AsyncImage
struct OptimizedAsyncImage<Content: View, Placeholder: View>: View {
    let url: String?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    init(
        url: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                content(Image(uiImage: loadedImage))
            } else if isLoading {
                placeholder()
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url, !url.isEmpty else {
            loadedImage = nil
            isLoading = false
            return
        }
        
        isLoading = true
        cacheManager.loadImage(from: url) { image in
            loadedImage = image
            isLoading = false
        }
    }
}

// MARK: - Convenience Initializers
extension OptimizedAsyncImage where Content == Image, Placeholder == Color {
    init(url: String?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - Profile Image View
struct OptimizedProfileImageView: View {
    let imageURL: String?
    let size: CGFloat
    let initials: String
    
    var body: some View {
        OptimizedAsyncImage(url: imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .clipShape(Circle())
        } placeholder: {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(.gray)
                )
        }
    }
}

// MARK: - Community Image View
struct OptimizedCommunityImageView: View {
    let imageURL: String?
    let size: CGFloat
    let initials: String
    
    var body: some View {
        OptimizedAsyncImage(url: imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .cornerRadius(8)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundColor(.gray)
                )
        }
    }
}

// MARK: - Bet Image View
struct OptimizedBetImageView: View {
    let imageURL: String?
    let size: CGFloat
    let initials: String
    
    var body: some View {
        OptimizedAsyncImage(url: imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .cornerRadius(8)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundColor(.gray)
                )
        }
    }
}
