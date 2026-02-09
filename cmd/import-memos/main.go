// import-memos imports all memos/notes from a Memos instance into a Notes
// instance using each application's REST API.
//
// Usage:
//
//	import-memos \
//	  --memos-url http://localhost:8081 \
//	  --memos-token <personal-access-token> \
//	  --notes-url http://localhost:3000 \
//	  [--dry-run]
//
// Limitations:
//   - Memo relations, reactions, and comments are not migrated.
//   - Memos visibility (PRIVATE/PROTECTED/PUBLIC) has no equivalent — all
//     imported notes are private to the mapped Notes user.
//   - Shares are not migrated.
//   - Tag colors default to #6b7280 (gray) since Memos tags have no color.
//   - Attachments larger than 25 MB are skipped with a warning.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

const (
	defaultTagColor          = "#6b7280"
	maxAttachmentBytes int64 = 25 * 1024 * 1024 // 25 MB
)

func main() {
	memosURL := flag.String("memos-url", "", "Base URL of the Memos instance (e.g. http://localhost:8081)")
	memosToken := flag.String("memos-token", "", "Personal Access Token for the Memos instance")
	notesURL := flag.String("notes-url", "", "Base URL of the Notes instance (e.g. http://localhost:3000)")
	dryRun := flag.Bool("dry-run", false, "Print what would be done without writing to Notes")
	flag.Parse()

	if *memosURL == "" || *memosToken == "" || *notesURL == "" {
		fmt.Fprintln(os.Stderr, "Error: --memos-url, --memos-token, and --notes-url are required")
		flag.Usage()
		os.Exit(1)
	}

	memosClient := NewMemosClient(*memosURL, *memosToken)
	fmt.Print("Connecting to Memos... ")
	if err := memosClient.Ping(); err != nil {
		fmt.Fprintf(os.Stderr, "\nError: cannot connect to Memos at %s: %v\n", *memosURL, err)
		os.Exit(1)
	}
	fmt.Println("OK")

	// Fetch Memos users.
	memosUsers, err := memosClient.ListUsers()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error listing Memos users: %v\n", err)
		os.Exit(1)
	}

	// Interactive user mapping.
	mappings, err := promptUserMappings(memosUsers, *notesURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nMigrating %d user(s)...\n", len(mappings))

	allStats := make(map[string]*MigrationStats)
	for _, m := range mappings {
		stats := migrateUser(memosClient, *notesURL, m, *dryRun)
		allStats[m.MemosUsername] = stats
	}

	// Print summary.
	printSummary(allStats)
}

// migrateUser performs the full migration for one Memos→Notes user mapping.
func migrateUser(memosClient *MemosClient, notesURL string, mapping UserMapping, dryRun bool) *MigrationStats {
	stats := &MigrationStats{}
	label := fmt.Sprintf("[%s]", mapping.MemosUsername)

	notesClient := NewNotesClient(notesURL, mapping.NotesToken)

	fmt.Printf("\n%s Syncing tags...\n", label)
	tagMap, err := syncTags(memosClient, notesClient, mapping.MemosUserName, dryRun, stats)
	if err != nil {
		msg := fmt.Sprintf("tag sync failed: %v", err)
		fmt.Printf("%s Error: %s\n", label, msg)
		stats.Errors = append(stats.Errors, msg)
		return stats
	}
	fmt.Printf("%s Tags ready (%d new)\n", label, stats.TagsCreated)

	fmt.Printf("%s Fetching memos...\n", label)
	memos, err := memosClient.ListAllMemos(mapping.MemosUserName)
	if err != nil {
		msg := fmt.Sprintf("fetching memos failed: %v", err)
		fmt.Printf("%s Error: %s\n", label, msg)
		stats.Errors = append(stats.Errors, msg)
		return stats
	}
	fmt.Printf("%s Found %d memo(s)\n", label, len(memos))

	for i, memo := range memos {
		progress := fmt.Sprintf("%s [%d/%d]", label, i+1, len(memos))
		migrateOneMemo(memosClient, notesClient, memo, tagMap, progress, dryRun, stats)
	}

	return stats
}

// syncTags ensures all Memos tags exist in the Notes instance and returns a
// name→ID map.
func syncTags(memosClient *MemosClient, notesClient *NotesClient, memosUserName string, dryRun bool, stats *MigrationStats) (map[string]int, error) {
	// Get Memos tag names from user stats.
	userStats, err := memosClient.GetUserStats(memosUserName)
	if err != nil {
		return nil, err
	}

	var memosTagNames []string
	for name := range userStats.TagCount {
		memosTagNames = append(memosTagNames, name)
	}

	if dryRun {
		tagMap := make(map[string]int)
		for i, name := range memosTagNames {
			fmt.Printf("  [dry-run] Would create tag %q (if not exists)\n", name)
			tagMap[strings.ToLower(name)] = i + 1
		}
		stats.TagsCreated = len(memosTagNames) // approximate
		return tagMap, nil
	}

	// Get existing Notes tags.
	existingTags, err := notesClient.ListTags()
	if err != nil {
		return nil, fmt.Errorf("listing Notes tags: %w", err)
	}

	tagMap := make(map[string]int)
	for _, t := range existingTags {
		tagMap[strings.ToLower(t.Name)] = t.ID
	}

	// Create missing tags.
	for _, name := range memosTagNames {
		lower := strings.ToLower(name)
		if _, exists := tagMap[lower]; exists {
			continue
		}

		tag, err := notesClient.CreateTag(name, defaultTagColor)
		if err != nil {
			return nil, fmt.Errorf("creating tag %q: %w", name, err)
		}
		tagMap[strings.ToLower(tag.Name)] = tag.ID
		stats.TagsCreated++
	}

	return tagMap, nil
}

// extractTitle splits the memo content into a title and body. If the content
// starts with a markdown H1 heading (# ...), that becomes the title and the
// remainder is the body. Otherwise title is empty.
func extractTitle(content string) (title, body string) {
	lines := strings.SplitN(content, "\n", 2)
	firstLine := strings.TrimSpace(lines[0])
	if strings.HasPrefix(firstLine, "# ") {
		title = strings.TrimSpace(strings.TrimPrefix(firstLine, "# "))
		if len(lines) > 1 {
			body = strings.TrimLeft(lines[1], "\n")
		}
		return title, body
	}
	return "", content
}

// migrateOneMemo creates a single note from a memo, including attachments.
func migrateOneMemo(memosClient *MemosClient, notesClient *NotesClient, memo MemosMemo, tagMap map[string]int, progress string, dryRun bool, stats *MigrationStats) {
	title, body := extractTitle(memo.Content)

	// Resolve tag IDs.
	var tagIDs []int
	for _, t := range memo.Tags {
		if id, ok := tagMap[strings.ToLower(t)]; ok {
			tagIDs = append(tagIDs, id)
		}
	}

	nAttachments := len(memo.Attachments)
	desc := title
	if desc == "" {
		desc = memo.Snippet
		if len(desc) > 50 {
			desc = desc[:50] + "..."
		}
	}

	if dryRun {
		fmt.Printf("  %s Would create note %q (%d tags, %d attachments, pinned=%v, archived=%v)\n",
			progress, desc, len(tagIDs), nAttachments, memo.Pinned, memo.State == "ARCHIVED")
		fmt.Printf("           Created: %s  Updated: %s\n", memo.CreateTime.Format("2006-01-02 15:04"), memo.UpdateTime.Format("2006-01-02 15:04"))
		stats.NotesCreated++
		return
	}

	// Determine max_size: if body is longer than 32K, raise the limit.
	maxSize := 0
	if len(body) > 32768 {
		maxSize = len(body) + 1024 // some headroom
	}

	note, err := notesClient.CreateNote(title, body, memo.Pinned, tagIDs, maxSize, memo.CreateTime, memo.UpdateTime)
	if err != nil {
		msg := fmt.Sprintf("creating note from memo %s: %v", memo.Name, err)
		fmt.Printf("  %s Error: %s\n", progress, msg)
		stats.Errors = append(stats.Errors, msg)
		return
	}
	stats.NotesCreated++

	// Archive if the memo was archived.
	if memo.State == "ARCHIVED" {
		if err := notesClient.ArchiveNote(note.ID); err != nil {
			msg := fmt.Sprintf("archiving note %d: %v", note.ID, err)
			fmt.Printf("  %s Warning: %s\n", progress, msg)
			stats.Errors = append(stats.Errors, msg)
		}
	}

	// Download and upload attachments.
	if nAttachments > 0 {
		var files []FileData
		for _, att := range memo.Attachments {
			if att.Size > maxAttachmentBytes {
				msg := fmt.Sprintf("skipping attachment %q (%d MB) — exceeds 25 MB limit", att.Filename, att.Size/(1024*1024))
				fmt.Printf("  %s Warning: %s\n", progress, msg)
				stats.Errors = append(stats.Errors, msg)
				continue
			}

			fd, err := memosClient.DownloadAttachment(att.Name, att.Filename)
			if err != nil {
				msg := fmt.Sprintf("downloading attachment %q from memo %s: %v", att.Filename, memo.Name, err)
				fmt.Printf("  %s Warning: %s\n", progress, msg)
				stats.Errors = append(stats.Errors, msg)
				continue
			}
			files = append(files, *fd)
		}

		if len(files) > 0 {
			if err := notesClient.UploadAttachments(note.ID, files); err != nil {
				msg := fmt.Sprintf("uploading attachments to note %d: %v", note.ID, err)
				fmt.Printf("  %s Warning: %s\n", progress, msg)
				stats.Errors = append(stats.Errors, msg)
			} else {
				stats.AttachmentsUploaded += len(files)
			}
		}
	}

	fmt.Printf("  %s Created note #%d %q (%d tags, %d attachments)\n",
		progress, note.ID, desc, len(tagIDs), nAttachments)
	fmt.Printf("           Timestamps preserved: created %s, updated %s\n",
		memo.CreateTime.Format("2006-01-02 15:04"), memo.UpdateTime.Format("2006-01-02 15:04"))
}

// printSummary prints a final summary of the migration.
func printSummary(allStats map[string]*MigrationStats) {
	fmt.Println("\n========================================")
	fmt.Println("         Migration Summary")
	fmt.Println("========================================")

	totalNotes := 0
	totalTags := 0
	totalAttachments := 0
	totalErrors := 0

	for user, s := range allStats {
		fmt.Printf("\n  User: %s\n", user)
		fmt.Printf("    Notes created:       %d\n", s.NotesCreated)
		fmt.Printf("    Tags created:        %d\n", s.TagsCreated)
		fmt.Printf("    Attachments uploaded: %d\n", s.AttachmentsUploaded)
		if len(s.Errors) > 0 {
			fmt.Printf("    Errors:              %d\n", len(s.Errors))
			for _, e := range s.Errors {
				fmt.Printf("      - %s\n", e)
			}
		}
		totalNotes += s.NotesCreated
		totalTags += s.TagsCreated
		totalAttachments += s.AttachmentsUploaded
		totalErrors += len(s.Errors)
	}

	fmt.Println("\n  ──────────────────────────────────")
	fmt.Printf("  Totals: %d notes, %d tags, %d attachments", totalNotes, totalTags, totalAttachments)
	if totalErrors > 0 {
		fmt.Printf(", %d errors", totalErrors)
	}
	fmt.Println()
	fmt.Println("========================================")
}
