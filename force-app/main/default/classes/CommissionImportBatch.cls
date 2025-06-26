global class CommissionImportBatch implements Database.Batchable<String>, Database.Stateful{
    private Blob fileBlob;
    private Id importRecordId;
    private Id strVendorId;
    private integer totalLinesRead;
    Map<Dealer_Import_Data__c, String> failedRecordErrors = new Map<Dealer_Import_Data__c, String>();
    private List<Dealer_Import_Data__c> failedRecords = new List<Dealer_Import_Data__c>();
    public CommissionImportBatch(Blob fileBlob,Id importRecordId ,Id strVendorId) {
        this.fileBlob = fileBlob;
        this.importRecordId = importRecordId;
        this.strVendorId = strVendorId;
    }
    public Iterable<String> start(Database.BatchableContext BC){
        String fileContent = fileBlob.toString().replace('\r', '');
        List<String> lines = new List<String>();
        String currentLine = '';
        
        for (Integer i = 0; i < fileContent.length(); i++) {
            String ch = fileContent.substring(i, i + 1);
            
            if (ch == '\n') {
                lines.add(currentLine);
                currentLine = '';
            } else {
                currentLine += ch;
            }
        }
        if (!String.isEmpty(currentLine)) { 
            lines.add(currentLine); 
            totalLinesRead = lines.size();
        }
        
        System.debug('Total Lines Read: ' + lines.size());
        
        if (!lines.isEmpty()) {
            lines.remove(0);
        }
        
        return lines;
    }
    public void execute(Database.BatchableContext BC, List<String> records) {
        
    }
    global void finish(Database.BatchableContext BC) {

    }
    public static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();
        Boolean insideQuote = false;
        String currentValue = '';
        
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            
            if (ch == '"') {
                if (insideQuote && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    currentValue += '"';
                    i++;
                } else {
                    insideQuote = !insideQuote;
                }
            } else if (ch == ',' && !insideQuote) {
                values.add(currentValue.trim());
                currentValue = '';
            } else {
                currentValue += ch;
            }
        }
        
        values.add(currentValue.trim());
        return values;
    }
    
    @TestVisible
    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            throw new IllegalArgumentException('Date cannot be blank.');
        }
        
        dateStr = dateStr.replace('/', '-').trim();
        List<String> parts = dateStr.split('-');
        
        if (parts.size() != 3) {
            throw new IllegalArgumentException('Invalid date format. Expected format: MM-DD-YYYY.');
        }
        
        try {
            Integer month = Integer.valueOf(parts[0]);
            Integer day = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            
            return Date.newInstance(year, month, day);
        } catch (Exception e) {
            throw new IllegalArgumentException('Invalid date: ' + dateStr + '. Expected format: MM-DD-YYYY.');
        }
    }
    
    @TestVisible  
    private static Integer safeInteger(String value) {
        try {
            return Integer.valueOf(value.replace(',', '').trim());
        } catch (Exception e) {
            System.debug('Integer Conversion Failed for: ' + value);
            return 0;
        }
    }
    
    @TestVisible
    private static Decimal safeDecimal(String value) {
        if (String.isBlank(value)) return 0.0;
        
        String cleanedValue = '';
        for (Integer i = 0; i < value.length(); i++) {
            String ch = value.substring(i, i + 1);
            if ((ch >= '0' && ch <= '9') || ch == '.') {
                cleanedValue += ch;
            }
        }
        
        try {
            return Decimal.valueOf(cleanedValue);
        } catch (Exception e) {
            return 0.0;
        }
    }
    
}