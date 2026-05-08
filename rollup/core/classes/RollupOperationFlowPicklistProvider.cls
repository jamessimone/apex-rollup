public class RollupOperationFlowPicklistProvider extends VisualEditor.DynamicPicklist {
  private static final Set<String> SKIPPED_VALUES = new Set<String>{ 'DELETE', 'UPDATE' };

  public override VisualEditor.DataRow getDefaultValue() {
    return new VisualEditor.DataRow(Rollup.Op.COUNT.name(), Rollup.Op.COUNT.name());
  }

  public override VisualEditor.DynamicPickListRows getValues() {
    VisualEditor.DynamicPickListRows values = new VisualEditor.DynamicPickListRows();
    for (Rollup.Op operation : Rollup.Op.values()) {
      if (SKIPPED_VALUES.contains(operation.name().substringBefore('_')) == false) {
        values.addRow(new VisualEditor.DataRow(operation.name(), operation.name()));
      }
    }
    return values;
  }
}
