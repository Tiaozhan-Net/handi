package main

import (
	"fmt"
	"math/rand"
)

func main() {
	a := rand.Intn(101)
	var b, c int
	for c = 1; a != b; c++ {
		fmt.Println("请输入一个0-100的整数")
		fmt.Scanln(&b)
		if a > b {
			fmt.Println("猜小了")
		} else if a < b {
			fmt.Println("猜大了")
		} else {
			fmt.Println("胜利")
		}
	}
	fmt.Printf("使用 %d 次猜中\n", c)
}
