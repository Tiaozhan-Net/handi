package main

import (
	"fmt"
	"math/rand"
)

func main(){
	a := rand.Intn(101)
	var b, c int
	for c = 1; a != b; c++ {
		fmt.Println("请输入一个0-100的整数")
		fmt.Scanln(&b)
		if a > b {
			fmt.Println("猜小了，再来")
		} else if a < b {
			fmt.Println("猜大了，再来")
		} else {
			fmt.Println("恭喜你，猜对了")
		}
		fmt.Printf("共猜了 %d 次\n", c)
	}
}