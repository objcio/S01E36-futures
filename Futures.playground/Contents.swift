import Foundation
import PlaygroundSupport

typealias JSONDictionary = [String: Any]


struct Episode {
    let id: String
    let title: String
}

struct EpisodeDetails {
    let title: String
    let description: String
}

extension Episode {
    init?(dictionary: JSONDictionary) {
        guard let id = dictionary["id"] as? String,
            let title = dictionary["title"] as? String else { return nil }
        self.id = id
        self.title = title
    }
}

extension EpisodeDetails {
    init?(dictionary: Any) {
        guard let dictionary = dictionary as? JSONDictionary,
            let title = dictionary["title"] as? String,
            let description = dictionary["description"] as? String else { return nil }
        self.title = title
        self.description = description
    }
}


struct Resource<A> {
    let url: URL
    let parse: (Data) -> A?
}

extension Resource {
    init(url: URL, parseJSON: @escaping (Any) -> A?) {
        self.url = url
        self.parse = { data in
            let json = try? JSONSerialization.jsonObject(with: data, options: [])
            return json.flatMap(parseJSON)
        }
    }
}


extension Episode {
    static let all = Resource<[Episode]>(url: URL(string: "http://localhost:8000/episodes.json")!, parseJSON: { json in
        guard let dictionaries = json as? [JSONDictionary] else { return nil }
        return dictionaries.flatMap(Episode.init)
    })
    
    var details: Resource<EpisodeDetails> {
        let url = URL(string: "http://localhost:8000/episodes/\(id).json")!
        return Resource<EpisodeDetails>(url: url, parseJSON: EpisodeDetails.init)
    }
}


enum Result<A> {
    case success(A)
    case error(Error)
    
    init(_ value: A?, or error: Error) {
        if let value = value {
            self = .success(value)
        } else {
            self = .error(error)
        }
    }
}

extension Result {
    func map<B>(_ transform: (A) -> B) -> Result<B> {
        switch self {
        case .success(let value): return .success(transform(value))
        case .error(let error): return .error(error)
        }
    }
}

extension String: Error { }

final class Future<A> {
    var callbacks: [(Result<A>) -> ()] = []
    var cached: Result<A>?
    
    init(compute: (@escaping (Result<A>) -> ()) -> ()) {
        compute(self.send)
    }
    
    private func send(_ value: Result<A>) {
        assert(cached == nil)
        cached = value
        for callback in callbacks {
            callback(value)
        }
        callbacks = []
    }
    
    func onResult(callback: @escaping (Result<A>) -> ()) {
        if let value = cached {
            callback(value)
        } else {
            callbacks.append(callback)
        }
    }
    
    func flatMap<B>(transform: @escaping (A) -> Future<B>) -> Future<B> {
        return Future<B> { completion in
            self.onResult { result in
                switch result {
                case .success(let value):
                    transform(value).onResult(callback: completion)
                case .error(let error):
                    completion(.error(error))
                }
            }
        }
    }
}


final class Webservice {
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
    
    func load<A>(_ resource: Resource<A>) -> Future<A> {
        return Future { completion in
            session.dataTask(with: resource.url, completionHandler: { data, _, _ in
                guard let data = data else {
                    completion(.error("No data"))
                    return
                }
                completion(Result(resource.parse(data), or: "Couldn't parse data"))
            }).resume()
        }
    }
}


PlaygroundPage.current.needsIndefiniteExecution = true

let webservice = Webservice()

webservice.load(Episode.all)
    .flatMap { episodes in
        webservice.load(episodes[0].details)
    }
    .onResult { result in
        print(result)
}