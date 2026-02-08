package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// promptUserMappings interactively prompts the operator to map Memos users to
// Notes users by providing a Notes API token for each Memos user they want to
// migrate.
func promptUserMappings(memosUsers []MemosUser, notesURL string) ([]UserMapping, error) {
	scanner := bufio.NewScanner(os.Stdin)

	fmt.Println("\n=== Memos Users ===")
	// Filter to only active users.
	var activeUsers []MemosUser
	for _, u := range memosUsers {
		if u.State == "" || u.State == "NORMAL" {
			activeUsers = append(activeUsers, u)
		}
	}

	if len(activeUsers) == 0 {
		return nil, fmt.Errorf("no active users found in Memos")
	}

	for i, u := range activeUsers {
		email := u.Email
		if email == "" {
			email = "(no email)"
		}
		fmt.Printf("  %d. %s (%s) [%s]\n", i+1, u.DisplayName, u.Username, email)
	}

	fmt.Println("\nEnter the numbers of the Memos users to migrate (comma-separated), or 'all':")
	fmt.Print("> ")
	if !scanner.Scan() {
		return nil, fmt.Errorf("no input received")
	}
	input := strings.TrimSpace(scanner.Text())

	var selectedUsers []MemosUser
	if strings.EqualFold(input, "all") {
		selectedUsers = activeUsers
	} else {
		for _, part := range strings.Split(input, ",") {
			part = strings.TrimSpace(part)
			idx, err := strconv.Atoi(part)
			if err != nil || idx < 1 || idx > len(activeUsers) {
				fmt.Printf("  Warning: skipping invalid selection %q\n", part)
				continue
			}
			selectedUsers = append(selectedUsers, activeUsers[idx-1])
		}
	}

	if len(selectedUsers) == 0 {
		return nil, fmt.Errorf("no users selected for migration")
	}

	var mappings []UserMapping
	for _, mu := range selectedUsers {
		fmt.Printf("\nMapping Memos user: %s (%s)\n", mu.DisplayName, mu.Username)
		fmt.Printf("  Enter the Notes API token for this user's Notes account: ")
		if !scanner.Scan() {
			return nil, fmt.Errorf("no input received for token")
		}
		token := strings.TrimSpace(scanner.Text())
		if token == "" {
			fmt.Println("  Skipping (no token provided)")
			continue
		}

		// Verify the token works.
		client := NewNotesClient(notesURL, token)
		if err := client.Ping(); err != nil {
			fmt.Printf("  Warning: could not connect to Notes with this token: %v\n", err)
			fmt.Print("  Continue anyway? (y/n): ")
			if !scanner.Scan() {
				return nil, fmt.Errorf("no input received")
			}
			if !strings.HasPrefix(strings.ToLower(strings.TrimSpace(scanner.Text())), "y") {
				fmt.Println("  Skipping this user")
				continue
			}
		} else {
			fmt.Println("  ✓ Notes API connection verified")
		}

		mappings = append(mappings, UserMapping{
			MemosUserName:    mu.Name,
			MemosUsername:     mu.Username,
			MemosDisplayName: mu.DisplayName,
			NotesToken:       token,
		})
	}

	if len(mappings) == 0 {
		return nil, fmt.Errorf("no valid user mappings created")
	}

	return mappings, nil
}
