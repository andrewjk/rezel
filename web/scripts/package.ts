import { promises as fs } from "node:fs";
import path from "node:path";

const webDir = path.resolve(import.meta.dirname, "..");
const rootDir = path.resolve(webDir, "..");

// Read version from package.json
const packageJsonPath = path.join(webDir, "package.json");
const packageJson = JSON.parse(await fs.readFile(packageJsonPath, "utf-8"));
const version = packageJson.version;

console.log(`Packaging version ${version}...`);

// 1. Update version numbers in C#, Swift, and Zig
await updateCSharpVersion(version);
await updateSwiftVersion(version);
//await updateZigVersion(version);

// 2. Copy Swift files to sibling rezel-swift
const swiftSrc = path.join(rootDir, "swift");
const swiftDest = path.join(rootDir, "..", "rezel-swift");
console.log(`Copying ${swiftSrc} to ${swiftDest}`);
await clearDest(swiftDest);
await copyDirectory(swiftSrc, swiftDest, [".build"]);

/*
// 3. Copy Zig files to sibling rezel-zig
const zigSrc = path.join(rootDir, "zig");
const zigDest = path.join(rootDir, "..", "rezel-zig");
console.log(`Copying ${zigSrc} to ${zigDest}`);
await clearDest(zigDest);
await copyDirectory(zigSrc, zigDest, [".zig-cache", "zig-out", "zig-pkg"]);
*/

console.log("Packaging complete!");

async function updateCSharpVersion(version: string) {
	const csprojPath = path.join(rootDir, "dotnet", "Rezel", "Rezel.csproj");
	let content = await fs.readFile(csprojPath, "utf-8");

	// Check if Version element exists
	if (content.includes("<Version>")) {
		// Replace existing version
		content = content.replace(/<Version>[^<]*<\/Version>/, `<Version>${version}</Version>`);
	} else {
		// Add Version element after TargetFramework
		content = content.replace(
			/(<TargetFramework>[^<]*<\/TargetFramework>)/,
			`$1\n    <Version>${version}</Version>`,
		);
	}

	await fs.writeFile(csprojPath, content);
	console.log(`Updated C# version to ${version}`);
}

async function updateSwiftVersion(version: string) {
	const packageSwiftPath = path.join(rootDir, "swift", "Package.swift");
	let content = await fs.readFile(packageSwiftPath, "utf-8");

	// Check if version comment exists (we'll add it as a comment since Swift uses git tags)
	if (content.includes("// Version:")) {
		content = content.replace(/\/\/ Version: [^\n]*/, `// Version: ${version}`);
	} else {
		// Add version comment at the top
		content = `// Version: ${version}\n${content}`;
	}

	await fs.writeFile(packageSwiftPath, content);
	console.log(`Updated Swift version to ${version}`);
}

async function updateZigVersion(version: string) {
	const zonPath = path.join(rootDir, "zig", "build.zig.zon");
	let content = await fs.readFile(zonPath, "utf-8");

	// Update the version field
	content = content.replace(/\.version = "[^"]*"/, `.version = "${version}"`);

	await fs.writeFile(zonPath, content);
	console.log(`Updated Zig version to ${version}`);
}

async function copyDirectory(src: string, dest: string, excludeDirs: string[]): Promise<void> {
	// Ensure the destination exists
	await fs.mkdir(dest, { recursive: true });

	const entries = await fs.readdir(src, { withFileTypes: true });

	for (const entry of entries) {
		const srcPath = path.join(src, entry.name);
		const destPath = path.join(dest, entry.name);

		// Skip excluded directories
		if (entry.isDirectory() && excludeDirs.includes(entry.name)) {
			console.log(`  Skipping ${srcPath}`);
			continue;
		}

		if (entry.isDirectory()) {
			await copyDirectory(srcPath, destPath, excludeDirs);
		} else {
			await fs.copyFile(srcPath, destPath);
		}
	}
}

async function clearDest(dest: string) {
	const entries = await fs.readdir(dest, { withFileTypes: true });

	for (const entry of entries) {
		const destPath = path.join(dest, entry.name);

		// Skip git files and folders
		if (entry.name.includes("git")) {
			continue;
		}

		await fs.rm(destPath, { recursive: true });
		//if (entry.isDirectory()) {
		//	await copyDirectory(srcPath, destPath, excludeDirs);
		//} else {
		//	await fs.copyFile(srcPath, destPath);
		//}
	}
}
