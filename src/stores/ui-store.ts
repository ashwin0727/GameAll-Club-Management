import { create } from "zustand";

interface UiState {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  toggleSidebar: () => void;
  /**
   * The sports every page reports on. `null` = All Sports (the default); otherwise the subset ticked in the top
   * bar. Read it through `useSportFilter`, which checks it against the facility's real sports.
   */
  selectedSportIds: string[] | null;
  setSelectedSportIds: (ids: string[] | null) => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: false,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  selectedSportIds: null,
  setSelectedSportIds: (ids) => set({ selectedSportIds: ids }),
}));
