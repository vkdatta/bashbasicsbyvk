public class TaxService {
    public double calculateTax(double amount, double rate, double exemptions) {
        double taxable = amount - exemptions;
        if (taxable <= 0) {
            return 0.0;
        }
        double tax = taxable * rate;
        if (tax > 10000) {
            tax = tax - (tax * 0.02);
        }
        return Math.round(tax * 100.0) / 100.0;
    }

    public String describe(String name, int count) {
        StringBuilder sb = new StringBuilder();
        sb.append("Service ").append(name);
        sb.append(" handled ").append(count);
        sb.append(" requests");
        return sb.toString();
    }
}
