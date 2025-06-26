public class StringSimilarityUtil {
    // Calculate Levenshtein Distance efficiently
    public static Integer levenshteinDistance(String str1, String str2) {
        if (str1 == null) str1 = '';
        if (str2 == null) str2 = '';

        Integer len1 = str1.length(), len2 = str2.length();
        if (len1 == 0) return len2;
        if (len2 == 0) return len1;

        // Optimize memory: Use only two arrays instead of full 2D list
        List<Integer> prevRow = new List<Integer>();
        List<Integer> currRow = new List<Integer>();

        // Initialize previous row
        for (Integer j = 0; j <= len2; j++) {
            prevRow.add(j);
        }

        for (Integer i = 1; i <= len1; i++) {
            currRow.clear();
            currRow.add(i);

            for (Integer j = 1; j <= len2; j++) {
                Integer cost = (str1.charAt(i - 1) == str2.charAt(j - 1)) ? 0 : 1;
                currRow.add(Math.min(
                    Math.min(currRow[j - 1] + 1, prevRow[j] + 1),
                    prevRow[j - 1] + cost
                ));
            }

            // Swap rows
            List<Integer> temp = prevRow;
            prevRow = currRow;
            currRow = temp;
        }
        return prevRow[len2];
    }

    // Calculate similarity percentage (100% = identical)
    public static Decimal calculateSimilarity(String str1, String str2) {
        if (str1 == null) str1 = '';
        if (str2 == null) str2 = '';

        Integer maxLength = Math.max(str1.length(), str2.length());
        if (maxLength == 0) return 100;

        Integer distance = levenshteinDistance(str1, str2);
        return (1 - ((Decimal) distance / maxLength)) * 100;

    }
}