import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import { Store, runStoreExtension } from "@vehla/store-sdk";

const maximumJSONSize = 500 * 1024;
const maximumHashSize = 500 * 1024 * 1024;

function selectedFiles(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function requireFiles(value) {
  const files = selectedFiles(value);
  if (!files.length) throw new Error("Choose at least one file.");
  for (const file of files) {
    if (!file || typeof file.path !== "string" || !path.isAbsolute(file.path)) {
      throw new Error("Vehla returned invalid selected-file metadata.");
    }
  }
  return files;
}

function requireSingleFile(value) {
  const [file] = requireFiles(value);
  if (file.isDirectory) throw new Error("Choose a file instead of a folder.");
  return file;
}

function bytes(value) {
  if (!Number.isFinite(value)) return "Unknown";
  return new Intl.NumberFormat("en", {
    style: "unit",
    unit: "byte",
    notation: value >= 1_000_000 ? "compact" : "standard",
    maximumFractionDigits: 1,
  }).format(value);
}

async function directoryEntryCount(directoryPath) {
  let count = 0;
  const directory = await fs.opendir(directoryPath);
  for await (const _ of directory) {
    count += 1;
    if (count >= 10_000) return "10,000+";
  }
  return String(count);
}

async function inspect(file) {
  const stats = await fs.stat(file.path);
  return {
    ...file,
    size: stats.isDirectory() ? null : stats.size,
    isDirectory: stats.isDirectory(),
    modifiedAt: stats.mtime.toISOString(),
    permissions: `0${(stats.mode & 0o777).toString(8)}`,
    entries: stats.isDirectory()
      ? await directoryEntryCount(file.path)
      : null,
  };
}

function notification(result, enabled, title, body) {
  if (!enabled) return result;
  return {
    ...result,
    action: {
      type: "notify",
      title,
      value: body,
    },
  };
}

async function digest(file, algorithm) {
  const stats = await fs.stat(file.path);
  if (stats.size > maximumHashSize) {
    throw new Error("Files larger than 500 MB exceed this example’s command-time budget.");
  }
  return await new Promise((resolve, reject) => {
    const hash = createHash(algorithm);
    const stream = createReadStream(file.path);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", reject);
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

runStoreExtension(async (invocation) => {
  const values = invocation.context.formValues;
  if (!values) {
    throw new Error("File Toolkit requires a newer version of Vehla.");
  }

  switch (invocation.commandID) {
    case "inspect-files": {
      const files = requireFiles(values.files);
      const inspected = [];
      for (const file of files) inspected.push(await inspect(file));

      const report = inspected.map((file) => [
        file.name,
        `Path: ${file.path}`,
        `Kind: ${file.isDirectory ? "Folder" : file.contentType || "File"}`,
        `Size: ${file.isDirectory ? "—" : bytes(file.size)}`,
        `Modified: ${file.modifiedAt}`,
        `Permissions: ${file.permissions}`,
        ...(file.entries ? [`Entries: ${file.entries}`] : []),
      ].join("\n")).join("\n\n");

      const result = Store.view({
        title: `Inspected ${inspected.length} item${inspected.length === 1 ? "" : "s"}`,
        subtitle: "Selected file metadata",
        sections: [
          {
            title: "Summary",
            items: [
              {
                type: "text",
                text: `${inspected.filter((item) => item.isDirectory).length} folders and ${inspected.filter((item) => !item.isDirectory).length} files`,
              },
            ],
          },
          ...inspected.map((file) => ({
            title: file.name,
            items: [
              { type: "detail", label: "Path", value: file.path },
              {
                type: "detail",
                label: "Kind",
                value: file.isDirectory ? "Folder" : file.contentType || "File",
              },
              {
                type: "detail",
                label: "Size",
                value: file.isDirectory ? "—" : bytes(file.size),
              },
              { type: "detail", label: "Modified", value: file.modifiedAt },
              { type: "detail", label: "Permissions", value: file.permissions },
              ...(file.entries
                ? [{ type: "detail", label: "Entries", value: file.entries }]
                : []),
            ],
          })),
        ],
        actions: [
          {
            type: "copyText",
            value: report,
            label: "Copy Report",
            systemImage: "doc.on.doc",
          },
        ],
      });
      return notification(
        result,
        values.notifyWhenComplete === true,
        "File inspection complete",
        `Inspected ${inspected.length} selected item${inspected.length === 1 ? "" : "s"}.`,
      );
    }

    case "hash-file": {
      const file = requireSingleFile(values.file);
      const algorithm = values.algorithm === "sha512" ? "sha512" : "sha256";
      const hash = await digest(file, algorithm);
      const label = algorithm.toUpperCase().replace("SHA", "SHA-");
      const result = Store.view({
        title: `${label} calculated`,
        subtitle: file.name,
        sections: [
          {
            title: "Digest",
            items: [
              { type: "detail", label: "File", value: file.path },
              { type: "detail", label: "Algorithm", value: label },
              { type: "code", language: "text", text: hash },
            ],
          },
        ],
        actions: [
          {
            type: "copyText",
            value: hash,
            label: "Copy Digest",
            systemImage: "doc.on.doc",
          },
        ],
      });
      return notification(
        result,
        values.notifyWhenComplete === true,
        "File hash complete",
        `${label} is ready for ${file.name}.`,
      );
    }

    case "format-json": {
      const file = requireSingleFile(values.file);
      const stats = await fs.stat(file.path);
      if (stats.size > maximumJSONSize) {
        throw new Error("JSON files larger than 500 KB exceed the rich-result output limit.");
      }
      const source = await fs.readFile(file.path, "utf8");
      let parsed;
      try {
        parsed = JSON.parse(source);
      } catch (error) {
        throw new Error(`Invalid JSON: ${error instanceof Error ? error.message : error}`);
      }
      const indentation = values.indentation === "fourSpaces" ? 4 : 2;
      const formatted = JSON.stringify(parsed, null, indentation);
      return Store.view({
        title: "JSON formatted",
        subtitle: file.name,
        sections: [
          {
            title: "Source",
            items: [
              { type: "detail", label: "Path", value: file.path },
              { type: "detail", label: "Size", value: bytes(stats.size) },
            ],
          },
          {
            title: "Formatted JSON",
            items: [
              { type: "code", language: "json", text: formatted },
            ],
          },
        ],
        actions: [
          {
            type: "copyText",
            value: formatted,
            label: "Copy JSON",
            systemImage: "doc.on.doc",
          },
        ],
      });
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
