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
		fmt.Println("  Authenticate to the Notes account for this user.")
		fmt.Println("  To generate a Notes API token, run on the Notes server:")
		fmt.Println("    bin/rails 'api:generate_token[user@example.com]'")
		fmt.Println("")
		fmt.Println("    1. Enter an API token")
		fmt.Println("    2. Log in with email and password")
		fmt.Print("  Choice [1/2]: ")
		if !scanner.Scan() {
			return nil, fmt.Errorf("no input received")
		}
		choice := strings.TrimSpace(scanner.Text())

		var token string
		var client *NotesClient

		switch choice {
		case "2":
			// Log in with email/password.
			fmt.Print("  Email: ")
			if !scanner.Scan() {
				return nil, fmt.Errorf("no input received")
			}
			email := strings.TrimSpace(scanner.Text())

			fmt.Print("  Password: ")
			if !scanner.Scan() {
				return nil, fmt.Errorf("no input received")
			}
			password := strings.TrimSpace(scanner.Text())

			if email == "" || password == "" {
				fmt.Println("  Skipping (empty credentials)")
				continue
			}

			client = NewNotesClient(notesURL, "")
			var err error
			token, err = client.Authenticate(email, password)
			if err != nil {
				fmt.Printf("  Error: authentication failed: %v\n", err)
				fmt.Println("  Skipping this user")
				continue
			}
			fmt.Println("  ✓ Authenticated successfully")

		default:
			// Use an existing API token.
			fmt.Print("  API token: ")
			if !scanner.Scan() {
				return nil, fmt.Errorf("no input received for token")
			}
			token = strings.TrimSpace(scanner.Text())
			if token == "" {
				fmt.Println("  Skipping (no token provided)")
				continue
			}
			client = NewNotesClient(notesURL, token)
		}

		// Verify the token works.
		if err := client.Ping(); err != nil {
			fmt.Printf("  Warning: could not verify Notes API connection: %v\n", err)
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
