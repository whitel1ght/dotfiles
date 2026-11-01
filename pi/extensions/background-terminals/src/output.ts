import { createWriteStream, type WriteStream } from "node:fs";

const DEFAULT_TAIL_BYTES = 64 * 1024;
const DEFAULT_FILE_CAP = 64 * 1024 * 1024;

// One stream of a process. Everything is spilled to a file so nothing is lost,
// while a bounded tail stays in memory to keep reads and the /ps view cheap.
export class StreamCapture {
  totalBytes = 0;
  // Set once the file hit its cap; later output still reaches the tail.
  fileTruncated = false;
  readonly path: string;

  private tail: Buffer = Buffer.alloc(0);
  private fileBytes = 0;
  private readonly file: WriteStream;
  private readonly tailBytes: number;
  private readonly fileCap: number;

  constructor(path: string, tailBytes = DEFAULT_TAIL_BYTES, fileCap = DEFAULT_FILE_CAP) {
    this.path = path;
    this.tailBytes = tailBytes;
    this.fileCap = fileCap;
    this.file = createWriteStream(path);
    // A broken spill file must not take the whole session down with it.
    this.file.on("error", () => {
      this.fileTruncated = true;
    });
  }

  write(chunk: Buffer): void {
    this.totalBytes += chunk.length;

    this.tail = Buffer.concat([this.tail, chunk]);
    if (this.tail.length > this.tailBytes) {
      this.tail = this.tail.subarray(this.tail.length - this.tailBytes);
    }

    if (this.fileTruncated) return;
    const room = this.fileCap - this.fileBytes;
    if (chunk.length > room) {
      if (room > 0) this.file.write(chunk.subarray(0, room));
      this.fileBytes = this.fileCap;
      this.fileTruncated = true;
      return;
    }
    this.fileBytes += chunk.length;
    this.file.write(chunk);
  }

  // True when the in-memory tail no longer holds the start of the output.
  get tailIsPartial(): boolean {
    return this.totalBytes > this.tail.length;
  }

  text(): string {
    let text = this.tail.toString("utf8");
    if (this.tailIsPartial) {
      // The tail starts mid-line, possibly mid-character. Drop the stub.
      const newline = text.indexOf("\n");
      text = newline === -1 ? "" : text.slice(newline + 1);
    }
    return text;
  }

  end(): Promise<void> {
    if (this.file.closed || this.file.destroyed) return Promise.resolve();
    return new Promise((resolve) => {
      this.file.once("close", () => resolve());
      this.file.end();
    });
  }
}
