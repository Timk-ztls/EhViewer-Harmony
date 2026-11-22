/**
 * ui-widget · 图案锁单元（新增层，登记于 inventory/ui-widget.extra.txt）
 *
 * 上游对应物：app/src/main/java/com/hippo/widget/lockpattern/LockPatternView.java 的内部类
 *            `public static class Cell`（3×3 单元，9 个对象常量复用）
 * 为什么单独成文件：上游是嵌套类，ArkTS 里锁视图与 LockPatternUtils 都要用它；
 *                  放在 LockPatternView.ets 里会造成 Utils ↔ View 循环 import，故提为独立模块，
 *                  行为与上游 `Cell.of()` 的对象复用语义完全一致（全进程只有 9 个实例）。
 */
export class Cell {
  private static cells: Cell[] | null = null;

  readonly row: number;
  readonly column: number;

  private constructor(row: number, column: number) {
    Cell.checkRange(row, column);
    this.row = row;
    this.column = column;
  }

  static of(row: number, column: number): Cell {
    Cell.checkRange(row, column);
    if (Cell.cells === null) {
      const all: Cell[] = [];
      for (let i = 0; i < 3; i++) {
        for (let j = 0; j < 3; j++) {
          all.push(new Cell(i, j));
        }
      }
      Cell.cells = all;
    }
    return Cell.cells[row * 3 + column];
  }

  static checkRange(row: number, column: number): void {
    if (row < 0 || row > 2) {
      throw new Error('row must be in range 0-2');
    }
    if (column < 0 || column > 2) {
      throw new Error('column must be in range 0-2');
    }
  }

  getRow(): number {
    return this.row;
  }

  getColumn(): number {
    return this.column;
  }

  toString(): string {
    return `(row=${this.row},clmn=${this.column})`;
  }
}
