public class RollupCurrencyInfo {

  public String IsoCode { get; set; }
  public Decimal ConversionRate { get; set; }
  public Integer DecimalPlaces { get; set; }
  public Boolean IsCorporate { get; set; }

  public static Map<String, RollupCurrencyInfo> getCurrencyMap() {
    Map<String, RollupCurrencyInfo> currencyInfoMap = new Map<String, RollupCurrencyInfo>();
    if (UserInfo.isMultiCurrencyOrganization() == false) {
      return currencyInfoMap;
    }

    String query = 'SELECT IsoCode, ConversionRate, DecimalPlaces, IsCorporate FROM CurrencyType WHERE IsActive = TRUE';
    List<RollupCurrencyInfo> currencyTypes = (List<RollupCurrencyInfo>) JSON.deserialize(JSON.serialize(Database.query(query)), List<RollupCurrencyInfo>.class);
    for (RollupCurrencyInfo currencyType : currencyTypes) {
      currencyInfoMap.put(currencyType.IsoCode, currencyType);
    }
    return currencyInfoMap;
  }
}