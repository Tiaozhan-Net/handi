package main

import (
	"fmt"
	"math/rand"
)

func main() {
	a := rand.Intn(101)
	var b, c int
	for {
		fmt.Scanln(&b)
		c++
		if a > b {
			fmt.Println("猜小了")
		} else if a < b {
			fmt.Println("猜大了")
		} else {
			fmt.Println("胜利")
		}
		fmt.Printf("共猜了 %d 次\n", c)
		if a == b {
			break
		}
	}
}
