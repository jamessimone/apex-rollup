@IsTest
private class RollupOperationFlowPicklistProviderTest {
  @IsTest
  static void returnsCorrectDefault() {
    Assert.areEqual(Rollup.Op.COUNT.name(), new RollupOperationFlowPicklistProvider().getDefaultValue().getValue());
  }

  @IsTest
  static void returnsRollupOperationsAsValues() {
    Set<String> expected = new Set<String>();
    for (Rollup.Op operation : Rollup.Op.values()) {
      if (operation.name().contains('UPDATE') == false && operation.name().contains('DELETE') == false) {
        expected.add(operation.name());
      }
    }

    Set<String> actual = new Set<String>();
    for (VisualEditor.DataRow row : new RollupOperationFlowPicklistProvider().getValues().getDataRows()) {
      actual.add(row.getValue().toString());
      actual.add(row.getLabel().toString());
    }

    Assert.areEqual(expected, actual);
  }
}
