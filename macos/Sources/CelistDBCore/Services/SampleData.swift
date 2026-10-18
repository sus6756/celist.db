import Foundation
import GRDB

/// Creates a small, friendly sample database (customers/orders) used to
/// onboard first-time users.
public enum SampleDatabase {
    public static func create(at url: URL) throws {
        // Be idempotent: if the file already exists with our marker, skip.
        if FileManager.default.fileExists(atPath: url.path), isOurs(url: url) {
            return
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(path: url.path, configuration: configuration)

        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE customers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    email TEXT,
                    phone TEXT,
                    city TEXT,
                    is_vip INTEGER NOT NULL DEFAULT 0,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE TABLE products (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    sku TEXT UNIQUE,
                    price REAL NOT NULL DEFAULT 0,
                    in_stock INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: """
                CREATE TABLE orders (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    customer_id INTEGER NOT NULL REFERENCES customers(id),
                    product_id INTEGER NOT NULL REFERENCES products(id),
                    quantity INTEGER NOT NULL DEFAULT 1,
                    order_date DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)

            let customers: [(String, String, String, String, Int64)] = [
                ("Acme Widgets", "acme@example.com", "555-0100", "Springfield", 1),
                ("Beta Corp", "beta@example.com", "555-0111", "Riverton", 0),
                ("Gamma LLC", "gamma@example.com", "555-0122", "Lakewood", 0),
                ("Delta Systems", "delta@example.com", "555-0133", "Springfield", 1),
            ]
            for c in customers {
                let values: [(any DatabaseValueConvertible)?] = [c.0, c.1, c.2, c.3, c.4]
                try db.execute(
                    sql: "INSERT INTO customers (name, email, phone, city, is_vip) VALUES (?, ?, ?, ?, ?)",
                    arguments: StatementArguments(values)
                )
            }

            let products: [(String, String, Double, Int64)] = [
                ("Gadget", "GAD-100", 9.99, 42),
                ("Widget", "WID-200", 14.50, 10),
                ("Gizmo", "GIZ-300", 3.25, 120),
                ("Doodad", "DOO-400", 21.00, 5),
            ]
            for p in products {
                let values: [(any DatabaseValueConvertible)?] = [p.0, p.1, p.2, p.3]
                try db.execute(
                    sql: "INSERT INTO products (name, sku, price, in_stock) VALUES (?, ?, ?, ?)",
                    arguments: StatementArguments(values)
                )
            }

            let orders: [(Int64, Int64, Int64)] = [
                (1, 1, 3), (1, 2, 1), (2, 3, 5), (3, 1, 2), (4, 4, 1), (2, 2, 2)
            ]
            for o in orders {
                let values: [(any DatabaseValueConvertible)?] = [o.0, o.1, o.2]
                try db.execute(
                    sql: "INSERT INTO orders (customer_id, product_id, quantity) VALUES (?, ?, ?)",
                    arguments: StatementArguments(values)
                )
            }
        }
        try dbQueue.close()
    }

    private static func isOurs(url: URL) -> Bool {
        var configuration = Configuration()
        configuration.readonly = true
        guard let q = try? DatabaseQueue(path: url.path, configuration: configuration) else { return false }
        defer { try? q.close() }
        do {
            let exists = try q.read { db in try db.tableExists("customers") }
            return exists
        } catch {
            return false
        }
    }
}