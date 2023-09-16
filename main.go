package main

import (
  "fmt"
)

func main() {
  type Value struct {
    s string
    f float64
    i int
  }

v := new(Value)
v.s = "message"
  v.f = 0.1
  v.i = 100
  fmt.Printf("Hello World! value => %v\n", v)





      }
