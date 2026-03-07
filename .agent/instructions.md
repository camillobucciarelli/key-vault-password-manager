# Instructions for Antigravity

1. **Architecture**: Always follow Clean Architecture principles.
   - **Data**: Implement datasources (local/remote), models, and repository implementations.
   - **Domain**: Define entities, repository interfaces, and usecases. No external dependencies here.
   - **Presentation**: UI and State management (BLoC/Cubit only).
2. **State Management**: Use `flutter_bloc`. Keep business logic out of the UI.
3. **UI/UX**: 
   - Use updated Material 3 design patterns.
   - Keep designs robust, clean, modern, and accessible.
