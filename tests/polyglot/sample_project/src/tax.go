package main

import "math"

func CalcTax(amount float64, rate float64, exemptions float64) float64 {
	taxable := amount - exemptions
	if taxable <= 0 {
		return 0.0
	}
	tax := taxable * rate
	if tax > 10000 {
		tax = tax - (tax * 0.02)
	}
	return math.Round(tax*100) / 100
}

func Fibonacci(n int) []int {
	a, b := 0, 1
	result := []int{}
	for i := 0; i < n; i++ {
		result = append(result, a)
		a, b = b, a+b
	}
	return result
}
