// billing helpers
function computeTaxRate(amount, rate, exemptions) {
  let taxable = amount - exemptions;
  if (taxable <= 0) {
    return 0.0;
  }
  let tax = taxable * rate;
  if (tax > 10000) {
    tax = tax - (tax * 0.02);
  }
  return Math.round(tax * 100) / 100;
}

const fib = (count) => {
  let a = 0, b = 1;
  const out = [];
  for (let i = 0; i < count; i++) {
    out.push(a);
    [a, b] = [b, a + b];
  }
  return out;
};

function renderInvoiceRow(item) {
  const cells = [];
  cells.push("<td>" + item.name + "</td>");
  cells.push("<td>" + item.qty + "</td>");
  cells.push("<td>" + item.price.toFixed(2) + "</td>");
  return "<tr>" + cells.join("") + "</tr>";
}

module.exports = { computeTaxRate, fib, renderInvoiceRow };
