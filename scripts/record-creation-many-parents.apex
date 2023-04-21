Integer recordCreationCount = 1000;
Integer iteration = [SELECT COUNT() FROM Account] / recordCreationCount;
Integer recordOffset = recordCreationCount * iteration;
Integer childCountPerParent = 5;
String pad = '0000000000';

List<Account> parents = new List<Account>();
for (Integer i = recordOffset; i < (recordOffset + recordCreationCount); i++) {
  Account parent = new Account();
  Integer nameValue = recordOffset + i;
  parent.Name = String.valueOf(nameValue).leftPad(8, '0');
  parents.add(parent);
}
insert parents;

List<Opportunity> childrenRecords = new List<Opportunity>();
for (Account parent : parents) {
  for (Integer childIndex = 0; childIndex < childCountPerParent; childIndex++) {
    Opportunity child = new Opportunity(StageName = iteration.format(), CloseDate = System.today(), Name = 'Child ' + childIndex, Amount = childIndex);
    child.AccountId = parent.Id;
    childrenRecords.add(child);
  }
}
insert childrenRecords;