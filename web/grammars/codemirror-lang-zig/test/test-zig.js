import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

import { fileTests } from "@lezer/generator/dist/test";
import { parser } from "@ndim/lezer-zig";
let caseDir = path.dirname(fileURLToPath(import.meta.url));

for (let file of fs.readdirSync(caseDir)) {
	if (!file.endsWith(".txt")) continue;

	let name = /^[^.]*/.exec(file)[0];
	describe(name, () => {
		for (let { name, run } of fileTests(fs.readFileSync(path.join(caseDir, file), "utf8"), file))
			it(name, () => run(parser));
	});
}
