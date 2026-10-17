// Renders an Ollama Go chat template the way Ollama does, for tests:
// go run render_template.go <template-file> < messages.json
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"text/template"
)

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func main() {
	src, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	var messages []Message
	if err := json.NewDecoder(os.Stdin).Decode(&messages); err != nil {
		panic(err)
	}
	tmpl := template.Must(template.New("chat").Parse(string(src)))
	if err := tmpl.Execute(os.Stdout, map[string]any{"Messages": messages}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
