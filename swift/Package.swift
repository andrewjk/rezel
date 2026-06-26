// Version: 1.0.0
// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "Rezel",
	products: [
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "Rezel",
			targets: ["Rezel"]
		),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "Rezel",
			exclude: [
				"Grammars/javascript.grammar", "Grammars/javascript.grammar-config",
				"Grammars/json.grammar", "Grammars/json.grammar-config",
				"Grammars/html.grammar", "Grammars/html.grammar-config",
				"Grammars/cpp.grammar", "Grammars/cpp.grammar-config",
				"Grammars/css.grammar", "Grammars/css.grammar-config",
				"Grammars/go.grammar", "Grammars/go.grammar-config",
				"Grammars/java.grammar", "Grammars/java.grammar-config",
				"Grammars/php.grammar", "Grammars/php.grammar-config",
				"Grammars/python.grammar", "Grammars/python.grammar-config",
				"Grammars/rust.grammar", "Grammars/rust.grammar-config",
				"Grammars/sass.grammar", "Grammars/sass.grammar-config",
				"Grammars/xml.grammar", "Grammars/xml.grammar-config",
				"Grammars/yaml.grammar", "Grammars/yaml.grammar-config",
				"Grammars/zig.grammar", "Grammars/zig.grammar-config",
				"Grammars/csharp.grammar", "Grammars/csharp.grammar-config",
				"Grammars/bash.grammar", "Grammars/bash.grammar-config",
			]
		),
		.executableTarget(
			name: "RezelCodeGen",
			dependencies: ["Rezel"]
		),
		.testTarget(
			name: "RezelTests",
			dependencies: ["Rezel"]
		),
		.executableTarget(
			name: "Bench",
			dependencies: ["Rezel"]
		),
	],
	swiftLanguageModes: [.v6]
)
