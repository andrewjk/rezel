import PackagePlugin

@main
struct RezelCodeGenPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
		guard let sourceTarget = target as? SourceModuleTarget else { return [] }

		let grammarConfigs = sourceTarget.sourceFiles.filter { $0.path.extension == "grammar-config" }
		guard !grammarConfigs.isEmpty else { return [] }

		let codeGenTool = try context.tool(named: "RezelCodeGen")

		var commands: [Command] = []
		for configFile in grammarConfigs {
			let configPath = configFile.path
			let configName = configPath.stem
			let outputPath = context.pluginWorkDirectory.appending("\(configName)+Generated.swift")

			let grammarPath = configPath.removingLastExtension().appending("grammar")

			let args = [
				grammarPath.string,
				configPath.string,
				outputPath.string,
			]

			commands.append(.buildCommand(
				displayName: "Generating parser for \(configName)",
				executable: codeGenTool.path,
				arguments: args,
				inputFiles: [grammarPath, configPath],
				outputFiles: [outputPath]
			))
		}
		return commands
	}
}
