public abstract class RollupComparer {
  protected final Integer moveTowardFrontOfList = -1;
  protected final Integer moveTowardBackOfList = 1;

  public abstract Integer compare(Object o1, Object o2);

  public void sort(Object[] values) {
    ComparableItem[] wrappedItems = new List<ComparableItem>();

    for (Object value : values) {
      wrappedItems.add(new ComparableItem(this, value));
    }

    wrappedItems.sort();

    values.clear();
    for (ComparableItem item : wrappedItems) {
      values.add(item.value);
    }
  }

  private class ComparableItem implements System.Comparable {
    private final RollupComparer comparer;
    private final Object value;

    public ComparableItem(RollupComparer comparer, Object value) {
      this.comparer = comparer;
      this.value = value;
    }

    public Integer compareTo(Object o) {
      return this.comparer.compare(this.value, ((ComparableItem) o).value);
    }
  }
}
