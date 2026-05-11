public without sharing class RollupOperationFlowPicklistProvider extends VisualEditor.DynamicPicklist {
  private static final Set<String> SKIPPED_VALUES = new Set<String>{ 'DELETE', 'UPDATE' };

  public override VisualEditor.DataRow getDefaultValue() {
    return new VisualEditor.DataRow(RollupOperation.COUNT.name(), RollupOperation.COUNT.name());
  }

  public override VisualEditor.DynamicPickListRows getValues() {
    VisualEditor.DynamicPickListRows values = new VisualEditor.DynamicPickListRows();
    for (RollupOperation operation : RollupOperation.values()) {
      if (SKIPPED_VALUES.contains(operation.name().substringBefore('_')) == false) {
        values.addRow(new VisualEditor.DataRow(operation.name(), operation.name()));
      }
    }
    return values;
  }
}
