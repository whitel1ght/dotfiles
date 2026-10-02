// Terminals that finished on their own and still owe the model a wake-up.
//
// A finish is deferred while the agent is busy and delivered once, in one
// message, when it goes idle. Anything the model already looked at in the
// meantime (bg_output, bg_stop) is consumed and never delivered.
export class WakeQueue<T extends { id: string }> {
  private readonly pending = new Map<string, T>();

  get size(): number {
    return this.pending.size;
  }

  defer(item: T): void {
    this.pending.set(item.id, item);
  }

  consume(id: string): boolean {
    return this.pending.delete(id);
  }

  drain(): T[] {
    const items = [...this.pending.values()];
    this.pending.clear();
    return items;
  }
}
