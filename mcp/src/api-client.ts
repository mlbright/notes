interface AuthConfig {
  baseUrl: string;
  email: string;
  password: string;
}

interface PaginationMeta {
  page: number;
  limit: number;
  pages: number;
  count: number;
}

export class NotesApiClient {
  private baseUrl: string;
  private email: string;
  private password: string;
  private token: string | null = null;
  private tokenExpiresAt: Date | null = null;

  constructor(config: AuthConfig) {
    this.baseUrl = config.baseUrl.replace(/\/+$/, "");
    this.email = config.email;
    this.password = config.password;
  }

  private async authenticate(): Promise<void> {
    const res = await fetch(`${this.baseUrl}/api/v1/auth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: this.email, password: this.password }),
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Authentication failed (${res.status}): ${body}`);
    }

    const data = (await res.json()) as {
      token: string;
      expires_at: string;
    };
    this.token = data.token;
    this.tokenExpiresAt = new Date(data.expires_at);
  }

  private isTokenExpired(): boolean {
    if (!this.token || !this.tokenExpiresAt) return true;
    // Refresh 5 minutes before expiry
    return new Date() >= new Date(this.tokenExpiresAt.getTime() - 5 * 60_000);
  }

  private async ensureAuthenticated(): Promise<void> {
    if (this.isTokenExpired()) {
      await this.authenticate();
    }
  }

  private async request<T>(
    method: string,
    path: string,
    options: { body?: unknown; params?: Record<string, string> } = {}
  ): Promise<T> {
    await this.ensureAuthenticated();

    const url = new URL(`${this.baseUrl}${path}`);
    if (options.params) {
      for (const [key, value] of Object.entries(options.params)) {
        if (value !== undefined && value !== "") {
          url.searchParams.set(key, value);
        }
      }
    }

    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.token}`,
      Accept: "application/json",
    };

    const fetchOptions: RequestInit = { method, headers };

    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json";
      fetchOptions.body = JSON.stringify(options.body);
    }

    const res = await fetch(url.toString(), fetchOptions);
    const text = await res.text();

    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      json = { raw: text };
    }

    if (!res.ok) {
      const msg =
        typeof json === "object" && json !== null && "error" in json
          ? (json as { error: string }).error
          : text;
      throw new ApiError(res.status, msg);
    }

    return json as T;
  }

  // ── Notes ──

  async listNotes(params: {
    filter?: string;
    tag?: string;
    sort?: string;
    direction?: string;
    page?: string;
  }): Promise<unknown> {
    const queryParams: Record<string, string> = {};
    if (params.filter) queryParams.filter = params.filter;
    if (params.tag) queryParams.tag = params.tag;
    if (params.sort) queryParams.sort = params.sort;
    if (params.direction) queryParams.direction = params.direction;
    if (params.page) queryParams.page = params.page;

    return this.request("GET", "/api/v1/notes", { params: queryParams });
  }

  async getNote(id: number): Promise<unknown> {
    return this.request("GET", `/api/v1/notes/${id}`);
  }

  async createNote(data: {
    title?: string;
    body?: string;
    pinned?: boolean;
    tag_ids?: number[];
  }): Promise<unknown> {
    return this.request("POST", "/api/v1/notes", { body: data });
  }

  async updateNote(
    id: number,
    data: {
      title?: string;
      body?: string;
      pinned?: boolean;
      tag_ids?: number[];
    }
  ): Promise<unknown> {
    return this.request("PATCH", `/api/v1/notes/${id}`, { body: data });
  }

  async deleteNote(id: number): Promise<unknown> {
    return this.request("DELETE", `/api/v1/notes/${id}`);
  }

  async searchNotes(query: string, page?: string): Promise<unknown> {
    const params: Record<string, string> = { q: query };
    if (page) params.page = page;
    return this.request("GET", "/api/v1/notes/search", { params });
  }

  async togglePin(id: number): Promise<unknown> {
    return this.request("PATCH", `/api/v1/notes/${id}/toggle_pin`);
  }

  async archiveNote(id: number): Promise<unknown> {
    return this.request("PATCH", `/api/v1/notes/${id}/archive`);
  }

  async unarchiveNote(id: number): Promise<unknown> {
    return this.request("PATCH", `/api/v1/notes/${id}/unarchive`);
  }

  async restoreNote(id: number): Promise<unknown> {
    return this.request("PATCH", `/api/v1/notes/${id}/restore`);
  }

  async listTrash(page?: string): Promise<unknown> {
    const params: Record<string, string> = {};
    if (page) params.page = page;
    return this.request("GET", "/api/v1/notes/trash", { params });
  }

  // ── Tags ──

  async listTags(): Promise<unknown> {
    return this.request("GET", "/api/v1/tags");
  }

  async createTag(data: { name: string; color?: string }): Promise<unknown> {
    return this.request("POST", "/api/v1/tags", { body: data });
  }

  // ── Shares ──

  async listShares(noteId: number): Promise<unknown> {
    return this.request("GET", `/api/v1/notes/${noteId}/shares`);
  }

  async shareNote(noteId: number, email: string): Promise<unknown> {
    return this.request("POST", `/api/v1/notes/${noteId}/shares`, {
      body: { email },
    });
  }

  async revokeShare(noteId: number, shareId: number): Promise<unknown> {
    return this.request("DELETE", `/api/v1/notes/${noteId}/shares/${shareId}`);
  }
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string
  ) {
    super(message);
    this.name = "ApiError";
  }
}
